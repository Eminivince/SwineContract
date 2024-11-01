// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SwineStake
 * @notice This contract allows users to stake tokens in two modes: Fixed and Flexible.
 * - Fixed Staking: Users lock tokens for a fixed period (30 days) and earn rewards at a fixed APY.
 * - Flexible Staking: Users can stake and unstake at any time, earning rewards every 6 hours.
 * The APYs can be updated by the contract owner.
 */
contract SwineStake is Ownable {
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    PiggyBank public piggyBank; // Instance of PiggyBank

    /// @dev APYs for staking modes (expressed in basis points, where 10000 = 100%)
    uint256 public fixedAPY; // 3000 = 30%
    uint256 public flexibleAPY; // 1000 = 10%

    /// @dev Lock period for fixed staking (in seconds)
    uint256 public fixedLockPeriod; // 30 days

    /// @dev Reward accumulation interval for flexible staking (in seconds)
    uint256 public flexibleRewardInterval; // 6 hours

    /// @dev Constants for time calculations
    uint256 public constant SECONDS_PER_YEAR = 31536000; // 365 days * 24 hours * 60 minutes * 60 seconds

    /// @dev Information about a user's fixed stake
    struct FixedStake {
        uint256 stakeId; // Unique ID of the stake
        uint256 amount; // Amount staked
        uint256 startTime; // Timestamp when staking started
        bool withdrawn; // Whether the stake has been withdrawn
        uint256 expectedReward; // Expected reward for this stake
    }

    /// @dev Information about a user's flexible stake
    struct FlexibleStake {
        uint256 amount; // Amount staked
        uint256 lastClaimTime; // Last timestamp when rewards were claimed
    }

    /// @dev Mapping from stakeId to FixedStake
    mapping(uint256 => FixedStake) public fixedStakes;

    /// @dev Mapping of user addresses to their fixed stake IDs
    mapping(address => uint256[]) public userFixedStakes;

    /// @dev Counter for the next fixed stake ID
    uint256 public nextFixedStakeId;

    /// @dev Mapping of user addresses to their flexible stakes
    mapping(address => FlexibleStake) public flexibleStakes;

    /// @dev Mapping from stakeId to owner address for fixed stakes
    mapping(uint256 => address) public fixedStakeOwners;

    /// @dev Events
    event FixedStaked(address indexed user, uint256 stakeId, uint256 amount);
    event FixedUnstaked(
        address indexed user,
        uint256 stakeId,
        uint256 amount,
        uint256 reward
    );
    event FlexibleStaked(address indexed user, uint256 amount);
    event FlexibleUnstaked(address indexed user, uint256 amount);
    event FlexibleRewardsClaimed(address indexed user, uint256 reward);
    event APYUpdated(uint256 newFixedAPY, uint256 newFlexibleAPY);
    event FixedLockPeriodUpdated(
        uint256 oldFixedLockPeriod,
        uint256 newFixedLockPeriod
    );
    event FlexibleRewardIntervalUpdated(
        uint256 oldFlexibleRewardInterval,
        uint256 newFlexibleRewardInterval
    );

    /**
     * @dev Constructor to initialize contract variables with known values
     * @param _stakingToken Address of the staking token (e.g., SWINE)
     * @param _rewardToken Address of the reward token
     * @param _piggyBank Address of the PiggyBank token contract
     */
    constructor(
        address _stakingToken,
        address _rewardToken,
        address _piggyBank
    ) Ownable(msg.sender) {
        require(_stakingToken != address(0), "Invalid staking token address");
        require(_rewardToken != address(0), "Invalid reward token address");
        require(_piggyBank != address(0), "Invalid PiggyBank address");
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        piggyBank = PiggyBank(_piggyBank);

        // Initialize APYs
        fixedAPY = 3000; // 30%
        flexibleAPY = 1000; // 10%

        // Initialize lock periods
        fixedLockPeriod = 30 days; // 30 days in seconds
        flexibleRewardInterval = 6 hours; // 6 hours in seconds

        nextFixedStakeId = 1; // Initialize stake ID counter
    }

    /**
     * @notice Allows the owner to update the APYs
     * @param _newFixedAPY New APY for fixed staking (in basis points)
     * @param _newFlexibleAPY New APY for flexible staking (in basis points)
     */
    function updateAPYs(
        uint256 _newFixedAPY,
        uint256 _newFlexibleAPY
    ) external onlyOwner {
        fixedAPY = _newFixedAPY;
        flexibleAPY = _newFlexibleAPY;
        emit APYUpdated(_newFixedAPY, _newFlexibleAPY);
    }

    /**
     * @notice Allows the owner to update the fixed lock period
     * @param _newFixedLockPeriod New fixed lock period in seconds
     */
    function updateFixedLockPeriod(
        uint256 _newFixedLockPeriod
    ) external onlyOwner {
        require(_newFixedLockPeriod > 0, "Lock period must be positive");
        uint256 oldFixedLockPeriod = fixedLockPeriod;
        fixedLockPeriod = _newFixedLockPeriod;
        emit FixedLockPeriodUpdated(oldFixedLockPeriod, _newFixedLockPeriod);
    }

    /**
     * @notice Allows the owner to update the flexible reward interval
     * @param _newFlexibleRewardInterval New flexible reward interval in seconds
     */
    function updateFlexibleRewardInterval(
        uint256 _newFlexibleRewardInterval
    ) external onlyOwner {
        require(
            _newFlexibleRewardInterval > 0,
            "Reward interval must be positive"
        );
        uint256 oldFlexibleRewardInterval = flexibleRewardInterval;
        flexibleRewardInterval = _newFlexibleRewardInterval;
        emit FlexibleRewardIntervalUpdated(
            oldFlexibleRewardInterval,
            _newFlexibleRewardInterval
        );
    }

    /**
     * @notice Allows users to stake tokens in fixed mode
     * @param _amount Amount of tokens to stake
     */
    function stakeFixed(uint256 _amount) external {
        require(_amount > 0, "Cannot stake zero tokens");

        // Calculate expected reward based on the fixed lock period
        uint256 expectedReward = calculateFixedReward(_amount);

        FixedStake memory newStake = FixedStake({
            stakeId: nextFixedStakeId,
            amount: _amount,
            startTime: block.timestamp,
            withdrawn: false,
            expectedReward: expectedReward
        });

        fixedStakes[nextFixedStakeId] = newStake;
        userFixedStakes[msg.sender].push(nextFixedStakeId);
        fixedStakeOwners[nextFixedStakeId] = msg.sender; // Set owner

        nextFixedStakeId++;

        // Transfer staking tokens from user to contract
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );

        // Mint PiggyBank tokens to user representing expected rewards
        piggyBank.mint(msg.sender, expectedReward);

        emit FixedStaked(msg.sender, newStake.stakeId, _amount);
    }

    /**
     * @notice Allows users to unstake tokens from fixed mode after lock period
     * @param _stakeId The ID of the stake to unstake
     */
    function unstakeFixed(uint256 _stakeId) external {
        require(fixedStakeOwners[_stakeId] == msg.sender, "Not your stake");

        FixedStake storage stake = fixedStakes[_stakeId];
        require(stake.amount > 0, "Stake does not exist");
        require(!stake.withdrawn, "Already withdrawn");
        require(
            block.timestamp >= stake.startTime + fixedLockPeriod,
            "Lock period not over"
        );

        uint256 reward = stake.expectedReward;
        stake.withdrawn = true;

        // Burn PiggyBank tokens from user representing the expected rewards
        piggyBank.burn(msg.sender, reward);

        // Transfer staked tokens back to user
        require(
            stakingToken.transfer(msg.sender, stake.amount),
            "Token transfer failed"
        );

        // Transfer reward tokens to user
        require(
            rewardToken.transfer(msg.sender, reward),
            "Reward transfer failed"
        );

        emit FixedUnstaked(msg.sender, _stakeId, stake.amount, reward);
    }

    function calculateFixedReward(
        uint256 _amount
    ) public view returns (uint256 reward) {
        uint256 stakingDuration = fixedLockPeriod;

        uint256 annualReward = (_amount * fixedAPY) / 10000;
        reward = (annualReward * stakingDuration) / SECONDS_PER_YEAR;
    }

    /**
     * @notice Allows users to stake tokens in flexible mode
     * @param _amount Amount of tokens to stake
     */
    function stakeFlexible(uint256 _amount) external {
        require(_amount > 0, "Cannot stake zero tokens");

        FlexibleStake storage stake = flexibleStakes[msg.sender];

        // If user already has a stake, claim rewards up to this point
        if (stake.amount > 0) {
            uint256 pendingReward = calculateFlexibleReward(msg.sender);
            stake.lastClaimTime = block.timestamp;
            if (pendingReward > 0) {
                require(
                    rewardToken.transfer(msg.sender, pendingReward),
                    "Reward transfer failed"
                );
                emit FlexibleRewardsClaimed(msg.sender, pendingReward);
            }
        } else {
            stake.lastClaimTime = block.timestamp;
        }

        stake.amount += _amount;
        require(
            stakingToken.transferFrom(msg.sender, address(this), _amount),
            "Transfer failed"
        );
        emit FlexibleStaked(msg.sender, _amount);
    }

    /**
     * @notice Allows users to unstake tokens from flexible mode
     * @param _amount Amount of tokens to unstake
     */
    function unstakeFlexible(uint256 _amount) external {
        FlexibleStake storage stake = flexibleStakes[msg.sender];
        require(
            stake.amount >= _amount && _amount > 0,
            "Invalid unstake amount"
        );

        uint256 timeSinceLastClaim = block.timestamp - stake.lastClaimTime;
        if (timeSinceLastClaim >= flexibleRewardInterval) {
            // User can claim rewards
            uint256 pendingReward = calculateFlexibleReward(msg.sender);
            if (pendingReward > 0) {
                require(
                    rewardToken.transfer(msg.sender, pendingReward),
                    "Reward transfer failed"
                );
                emit FlexibleRewardsClaimed(msg.sender, pendingReward);
            }
        } else {
            // Rewards are forfeited
            emit FlexibleRewardsClaimed(msg.sender, 0);
        }

        stake.amount -= _amount;
        stake.lastClaimTime = block.timestamp;

        require(
            stakingToken.transfer(msg.sender, _amount),
            "Token transfer failed"
        );
        emit FlexibleUnstaked(msg.sender, _amount);
    }

    /**
     * @notice Allows users to claim accumulated rewards in flexible staking
     */
    function claimFlexibleRewards() external {
        FlexibleStake storage stake = flexibleStakes[msg.sender];
        require(stake.amount > 0, "No flexible stake found");

        uint256 timeSinceLastClaim = block.timestamp - stake.lastClaimTime;
        require(
            timeSinceLastClaim >= flexibleRewardInterval,
            "Rewards not yet available"
        );

        uint256 rewardAmount = calculateFlexibleReward(msg.sender);
        require(rewardAmount > 0, "No rewards to claim");

        stake.lastClaimTime = block.timestamp;

        require(
            rewardToken.transfer(msg.sender, rewardAmount),
            "Reward transfer failed"
        );
        emit FlexibleRewardsClaimed(msg.sender, rewardAmount);
    }

    /**
     * @notice Calculates the reward for flexible staking
     * @param _user Address of the user
     * @return reward Amount of reward tokens
     */
    function calculateFlexibleReward(
        address _user
    ) public view returns (uint256 reward) {
        FlexibleStake storage stake = flexibleStakes[_user];
        uint256 stakingDuration = block.timestamp - stake.lastClaimTime;
        uint256 intervals = stakingDuration / flexibleRewardInterval;
        if (intervals == 0) {
            return 0;
        }
        // intervalReward = (stake.amount * flexibleAPY * flexibleRewardInterval) / (10000 * SECONDS_PER_YEAR)
        uint256 intervalReward = (stake.amount *
            flexibleAPY *
            flexibleRewardInterval) / (10000 * SECONDS_PER_YEAR);
        reward = intervals * intervalReward;
    }

    /**
     * @notice Allows the owner to withdraw tokens (for emergency purposes)
     * @param _token Address of the token to withdraw
     * @param _amount Amount to withdraw
     */
    function emergencyWithdraw(
        address _token,
        uint256 _amount
    ) external onlyOwner {
        require(_amount > 0, "Amount must be greater than zero");
        require(IERC20(_token).transfer(owner(), _amount), "Transfer failed");
    }

    /**
     * @notice Get the fixed stake IDs for a user
     * @param _user Address of the user
     * @return stakeIds Array of stake IDs
     */
    function getUserFixedStakes(
        address _user
    ) external view returns (uint256[] memory stakeIds) {
        uint256[] memory stakes = userFixedStakes[_user];
        return stakes;
    }
}

/**
 * @title PiggyBank
 * @dev Interface for the PiggyBank token.
 */
interface PiggyBank {
    function mint(address to, uint256 amount) external;

    function burn(address from, uint256 amount) external;
}
