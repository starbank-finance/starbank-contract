// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


interface ISBXToken {
    function mint(address _to, uint256 _amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

// It's MasterChef. fork from Sushi, etc...
// Have fun reading it. Hopefully it's bug-free. God bless.

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        int256 rewardDebt; // Reward debt. See explanation below.
    }
    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; 
        uint256 lastRewardTime;
        uint256 accRewardPerShare; 
    }
    // The reward TOKEN!
    ISBXToken public rewardToken;

    // Dev address.
    address public devAddress;
    // Treasury address.
    address public treasuryAddress;
    // Reserve1 address.
    address public reserve1Address;
    // Reserve2 address.
    address public reserve2Address;
    // Reserve3 address.
    address public reserve3Address;
    // communtyGrowth address.
    address public communtyGrowthAddress;

    // LP Mining Reward     57.00% (60% except for premint)
    // Community Growth     3.80% (4% except for premint)
    // Dev                  17.10% (18% except for premint)
    // Treasury             5.70% (6% except for premint)
    // Reserve for Potential Investors  11.40% (12% except for premint)

    // distribution percentages: a value of 1000 = 100%
    uint256 public constant POOL_PERCENTAGE = 600;
    uint256 public constant DEV_PERCENTAGE = 180;
    uint256 public constant RSERVE1_PERCENTAGE = 40;
    uint256 public constant RSERVE2_PERCENTAGE = 40;
    uint256 public constant RSERVE3_PERCENTAGE = 40;
    uint256 public constant TREASURY_PERCENTAGE = 60;
    uint256 public constant COMMUNITY_PERCENTAGE = 40;


    // reward tokens created per second.
    uint256 public rewardPerSecond;

    // set a max reward per second, which can never be higher than 10 per second
    uint256 public constant maxRewardPerSecond = 10e18;
    // 250000000 * 0.95 / 2 years = 325342.465/day
    // Average 3.75 / sec 

    uint256 public BONUS_MULTIPLIER = 1;
    uint256 public constant MaxAllocPoint = 4000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The timestamp when reward mining starts.
    uint256 public startTime;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EventHarvest(address indexed user, uint256 indexed pid, uint256 amount, address _to);

    event LogSetPool(
        uint256 indexed pid,
        uint256 allocPoint
    );
    uint256 private constant ACC_REWARD_PRECISION = 1e12;


    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        // Check if the given lpToken already exists in the pool.
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }
    constructor() {}

    function init(
        address _rewardToken,
        uint256 _startTime,
        uint256 _rewardPerSecond
        // ,
        // address _fund
    ) external  onlyOwner {
        require (startTime==0, "only one time.");
        require (address(_rewardToken) != address(0),"reward token address error") ;

        rewardToken = ISBXToken(_rewardToken);
        rewardPerSecond = _rewardPerSecond;
        startTime = _startTime;

        devAddress = msg.sender; // temporary 
        treasuryAddress = msg.sender;
        reserve1Address = msg.sender;
        reserve2Address = msg.sender;
        reserve3Address = msg.sender;
        communtyGrowthAddress = msg.sender;
        
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function addPool(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) public onlyOwner nonDuplicated(_lpToken) {
        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");
        require(address(rewardToken) != address(_lpToken), "reward token should not be lptoken");
        
        require(
            Address.isContract(address(_lpToken)),
            "add: LP token must be a valid contract"
        );
        
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accRewardPerShare: 0
            })
        );
        poolExistence[_lpToken] = true;
    }
 
    // Update the given pool's reward allocation point. Can only be called by the owner.
    function setPool(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate

    ) public onlyOwner {

        require(_allocPoint <= MaxAllocPoint, "add: too many alloc points!!");

        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        emit LogSetPool(
            _pid,
            _allocPoint
        );
    }

    // View function to see pending reward tokens on frontend.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
        if (startTime==0 || block.timestamp<startTime) {
            return uint256(0);
        }

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 delta = block.timestamp - pool.lastRewardTime;
            uint256 reward = (delta.mul(rewardPerSecond).mul(pool.allocPoint)).div(totalAllocPoint);

            // we take parts of the rewards for treasury, these can be subject to change, so we recalculate it
            // a value of 1000 = 100%
            uint256 rewardsForPool = (reward * POOL_PERCENTAGE) /
                1000;
            
            accRewardPerShare += (rewardsForPool.mul(ACC_REWARD_PRECISION)).div(lpSupply);
        }
        return uint256(int256((user.amount.mul(accRewardPerShare)).div(ACC_REWARD_PRECISION)) - (user.rewardDebt));
    }

    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // Update reward vairables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    function updatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        require(startTime!=0, 'not initilized yet');
        
        if (block.timestamp <= startTime) {
            return;
        }

        PoolInfo storage pool = poolInfo[_pid];
        if( pool.allocPoint==0 || rewardPerSecond == 0) {
            return ;
        }
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 reward = multiplier.mul(rewardPerSecond).mul(pool.allocPoint).div(totalAllocPoint);


        rewardToken.mint(reserve1Address, reward * RSERVE1_PERCENTAGE / 1000 );
        rewardToken.mint(reserve2Address, reward * RSERVE2_PERCENTAGE / 1000 );
        rewardToken.mint(reserve3Address, reward * RSERVE3_PERCENTAGE / 1000 );
        rewardToken.mint(treasuryAddress, reward * TREASURY_PERCENTAGE / 1000 );
        rewardToken.mint(devAddress, reward * DEV_PERCENTAGE / 1000 );
        rewardToken.mint(communtyGrowthAddress, reward * COMMUNITY_PERCENTAGE / 1000 );
        rewardToken.mint(address(this), reward * POOL_PERCENTAGE / 1000 );

        pool.accRewardPerShare = pool.accRewardPerShare.add(reward.mul(ACC_REWARD_PRECISION).div(lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for reward token allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        require(startTime!=0, 'not initilized yet');
        require(_amount > 0, "deposit should be more than 0");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require (_pid < poolInfo.length, "no exist");
        require(pool.allocPoint>0 , "cannot deposit this token for now");
        
        updatePool(_pid);

        // check balance before transfer. 
        uint256 bal1 = pool.lpToken.balanceOf(address(this));

        pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);

        // check balance after transfer. 
        uint256 bal2 = pool.lpToken.balanceOf(address(this));

        // check the diff , it's income value. 
        uint256 actual_amount = bal2-bal1;

        require(actual_amount==_amount, " income value should be same with the argument value. " );

        user.amount += actual_amount;
        user.rewardDebt += int256((actual_amount.mul( pool.accRewardPerShare)).div(ACC_REWARD_PRECISION));

        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount, address _to) public nonReentrant {
        require(startTime!=0, 'not initilized yet');
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (_to == address(0)) {
            _to = msg.sender;
        }
        require(user.amount >= _amount, "withdraw: not good");
        require(_amount > 0, "withdraw amount should be > 0");


        updatePool(_pid);

        // check 
        uint256 bal1 = pool.lpToken.balanceOf(address(this));

        user.rewardDebt -= int256((_amount.mul( pool.accRewardPerShare)) .div( ACC_REWARD_PRECISION));
        user.amount -= _amount;
        
        // transfer
        pool.lpToken.safeTransfer(address(msg.sender), _amount);

        // check 
        uint256 bal2 = pool.lpToken.balanceOf(address(this));

        assert((bal1 - bal2) == _amount);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        require(startTime!=0, 'not initilized yet');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        
    }


    function harvest(uint256 _pid, address _to) public nonReentrant {

        require(_to != address(0), "cannot withdraw to zero address");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        updatePool(_pid);

        int256 accumulatedReward = int256((user.amount.mul(pool.accRewardPerShare)) .div( ACC_REWARD_PRECISION));
        uint256 pending = uint256(accumulatedReward - user.rewardDebt);
        require(pending > 0, "no pending reward ");

        // Effects
        user.rewardDebt = accumulatedReward;
        // Interactions
        safeRewardTransfer(_to, pending);
        emit EventHarvest(msg.sender, _pid, pending, _to);
    }





    function harvestAll(address _to) external {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            if (userInfo[_pid][msg.sender].amount > 0) {
                harvest(_pid, _to);
            }
        }
    }

    function harvestSome(uint256[] calldata _pids, address _to) external {
        for (uint256 i = 0; i < _pids.length; i++) {
            if (userInfo[_pids[i]][msg.sender].amount > 0) {
                harvest(_pids[i], _to);
            }
        }
    }

    // Safe rewward token transfer function, 
    // just in case if rounding error causes pool to not have enough reward tokens.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 bal = rewardToken.balanceOf(address(this));
        if (_amount > bal) {
            rewardToken.transfer(_to, bal);
        } else {
            rewardToken.transfer(_to, _amount);
        }
    }

    function setRewardPerSecond(uint256 _rewardPerSecond, bool _withUpdate) external onlyOwner {
        require(_rewardPerSecond <= maxRewardPerSecond, "setRewardPerSecond: too many sbxs!");
        if (_withUpdate) {
            massUpdatePools();
        }
        rewardPerSecond = _rewardPerSecond;
    }

    // Update dev address by the previous dev.
    function dev(address _devAddress) public onlyOwner {
        devAddress = _devAddress;
    }
    // Update treasury address by the owner.
    function treasury(address _treasuryAddress) public onlyOwner {
        treasuryAddress = _treasuryAddress;
    }
    // Update reserve1 address by the owner.
    function reserve1(address _reserve1Address) public onlyOwner {
        reserve1Address = _reserve1Address;
    }
    // Update reserve2 address by the owner.
    function reserve2(address _reserve2Address) public onlyOwner {
        reserve2Address = _reserve2Address;
    }
    // Update reserve3 address by the owner.
    function reserve3(address _reserve3Address) public onlyOwner {
        reserve3Address = _reserve3Address;
    }
    // Update communtyGrowth address by the owner.
    function communtyGrowth(address _communtyGrowthAddress) public onlyOwner {
        communtyGrowthAddress = _communtyGrowthAddress;
    }
    function setStartTime(uint _startTime) external onlyOwner {
        require(startTime<block.timestamp, "already started");
        startTime = _startTime;
    }

}