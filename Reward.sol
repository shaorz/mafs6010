pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Reward is Ownable {
    IERC20 public societyToken;
    uint256 public rewardPool;
    uint256 public constant WEEK = 7 days;
    uint256 public lastRewardTime;

    struct Player {
        uint256 staked;
        uint256 lockEnd;
        uint256 playtime;
        uint256 lastClaim;
    }

    mapping(address => Player) public players;
    uint256 public totalStaked;
    uint256 public totalPlaytime;
    uint256 public alpha = 50;
    uint256 public beta = 50;

    event Staked(address player, uint256 amount, uint256 lockDuration);
    event PlaytimeAdded(address player, uint256 hours);
    event RewardClaimed(address player, uint256 amount);

    constructor(IERC20 _societyToken) {
        societyToken = _societyToken;
        lastRewardTime = block.timestamp;
    }

    // stake with locking PoS: longer lock period => higher yield 
    // TODO yield in terms of game assets 
    function stake(uint256 amount, uint256 lockDays) external {
        require(lockDays >= 1 && lockDays <= 365, "Lock period must be between 1 and 365 days");
        societyToken.transferFrom(msg.sender, address(this), amount);
        uint256 multiplier = 1 + (lockDays / 30); // 1x for 1 month, 2x for 2 months, etc.
        players[msg.sender].staked += amount * multiplier;
        players[msg.sender].lockEnd = block.timestamp + (lockDays * 1 days);
        totalStaked += amount * multiplier;
        emit Staked(msg.sender, amount, lockDays);
    }

    // unstake after lock period
    function unstake(uint256 amount) external{
        require(block.timestamp >= players[msg.sender].lockEnd, "Tokens are still locked");
        require(players[msg.sender].staked >= amount, "Insufficient staked amount");
        players[msg.sender].staked -= amount;
        totalStaked -= amount;
        societyToken.transfer(msg.sender, amount);
    }

    // add verified playtime in hours
    function addPlaytime(address player, uint256 hours) external onlyOwner {
        players[player].playtime += hours;
        totalPlaytime += hours;
        emit PlaytimeAdded(player, hours);
    }

    // fund the reward pool
    function fundRewardPool(uint256 amount) external {
        societyToken.transferFrom(msg.sender, address(this), amount);
        rewardPool += amount;
    }

    // claim rewards based on staked amount and playtime
    function claimReward() external {
        require(block.timestamp >= lastRewardTime + WEEK, "Too soon");
        Player storage p = players[msg.sender];
        require(p.lastClaim < lastRewardTime + WEEK, "Already claimed");

        uint256 normStake = (p.staked * 1e18) / totalStaked;  // Normalized with precision
        uint256 normPlay = (p.playtime * 1e18) / totalPlaytime;
        uint256 score = (alpha * normStake + beta * normPlay) / 100;
        uint256 reward = (score * rewardPool) / 1e18;  // Denormalize
        require(reward > 0, "No reward");

        p.lastClaim = block.timestamp;
        // Reset playtime for next cycle (optional; or accumulate with decay)
        p.playtime = 0;
        totalPlaytime = 0;  // Reset global

        societyToken.transfer(msg.sender, reward);
        rewardPool -= reward;  // Simplified; in practice, distribute all pool
        emit RewardClaimed(msg.sender, reward);
    }

    // Tune weights (DAO governance)
    function setWeights(uint256 _alpha, uint256 _beta) external onlyOwner {
        require(_alpha + _beta == 100, "Weights must sum to 100");
        alpha = _alpha;
        beta = _beta;
    }
}


