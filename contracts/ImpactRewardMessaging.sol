// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ImpactReward Messaging
 * @dev Reward users for messages with verified positive social impact
 * @author Swift v2 Team
 */
contract ImpactRewardMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum ImpactLevel { LOW, MEDIUM, HIGH, EXCEPTIONAL }

    // Events
    event ImpactMessageSubmitted(
        uint256 indexed messageId,
        address indexed creator,
        ImpactLevel expectedImpact,
        uint256 timestamp
    );

    event ImpactVerifiedAndRewarded(
        uint256 indexed messageId,
        address indexed creator,
        ImpactLevel verifiedImpact,
        uint256 rewardAmount,
        uint256 timestamp
    );

    // Structs
    struct ImpactRewardMessage {
        uint256 id;
        address creator;
        string title;
        string description;
        string actionTaken;
        ImpactLevel expectedImpact;
        ImpactLevel verifiedImpact;
        string proofUrl;
        address[] recipients;
        uint256 timestamp;
        bool isVerified;
        bool isRewarded;
        uint256 rewardAmount;
        address[] verifiers;
        mapping(address => ImpactLevel) verifierRatings;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => ImpactRewardMessage) public impactRewardMessages;
    mapping(address => uint256[]) public userMessages;
    mapping(address => uint256) public userTotalRewards;
    mapping(address => uint256) public userImpactMessages;
    mapping(address => bool) public approvedVerifiers;

    // Celo cUSD address
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Reward structure (in cUSD)
    uint256 public constant LOW_IMPACT_REWARD = 1000000000000000; // 0.001 cUSD
    uint256 public constant MEDIUM_IMPACT_REWARD = 5000000000000000; // 0.005 cUSD
    uint256 public constant HIGH_IMPACT_REWARD = 10000000000000000; // 0.01 cUSD
    uint256 public constant EXCEPTIONAL_IMPACT_REWARD = 50000000000000000; // 0.05 cUSD

    // Constants
    uint256 public constant MAX_TITLE_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 public constant MAX_RECIPIENTS = 100;
    uint256 public constant VERIFICATION_THRESHOLD = 2;

    // Reward pool
    uint256 public rewardPool;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Fund reward pool
     * @param _amount Amount to fund
     */
    function fundRewardPool(uint256 _amount) 
        external 
        nonReentrant 
    {
        require(_amount > 0, "Amount must be greater than 0");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        require(
            cusd.transferFrom(msg.sender, address(this), _amount),
            "Funding failed"
        );

        rewardPool += _amount;
    }

    /**
     * @dev Add approved verifier
     */
    function addVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "Invalid verifier");
        approvedVerifiers[_verifier] = true;
    }

    /**
     * @dev Remove verifier
     */
    function removeVerifier(address _verifier) external onlyOwner {
        approvedVerifiers[_verifier] = false;
    }

    /**
     * @dev Get reward amount for impact level
     */
    function getRewardAmount(ImpactLevel _level) public pure returns (uint256) {
        if (_level == ImpactLevel.LOW) return LOW_IMPACT_REWARD;
        if (_level == ImpactLevel.MEDIUM) return MEDIUM_IMPACT_REWARD;
        if (_level == ImpactLevel.HIGH) return HIGH_IMPACT_REWARD;
        if (_level == ImpactLevel.EXCEPTIONAL) return EXCEPTIONAL_IMPACT_REWARD;
        return 0;
    }

    /**
     * @dev Submit impact message for rewards
     * @param _title Message title
     * @param _description Description of impact
     * @param _actionTaken Action taken
     * @param _expectedImpact Expected impact level
     * @param _proofUrl URL to proof
     * @param _recipients People impacted
     */
    function submitImpactMessage(
        string memory _title,
        string memory _description,
        string memory _actionTaken,
        ImpactLevel _expectedImpact,
        string memory _proofUrl,
        address[] memory _recipients
    ) 
        external 
        nonReentrant 
    {
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_title).length <= MAX_TITLE_LENGTH, "Title too long");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        ImpactRewardMessage storage message = impactRewardMessages[messageId];
        message.id = messageId;
        message.creator = msg.sender;
        message.title = _title;
        message.description = _description;
        message.actionTaken = _actionTaken;
        message.expectedImpact = _expectedImpact;
        message.proofUrl = _proofUrl;
        message.timestamp = block.timestamp;
        message.isVerified = false;
        message.isRewarded = false;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0)) {
                message.recipients.push(_recipients[i]);
            }
        }

        userMessages[msg.sender].push(messageId);
        userImpactMessages[msg.sender]++;

        emit ImpactMessageSubmitted(
            messageId,
            msg.sender,
            _expectedImpact,
            block.timestamp
        );
    }

    /**
     * @dev Verify and rate impact (approved verifiers only)
     * @param _messageId ID of the message
     * @param _impactRating Verified impact level
     */
    function verifyImpact(uint256 _messageId, ImpactLevel _impactRating) 
        external 
        nonReentrant 
    {
        require(approvedVerifiers[msg.sender], "Not an approved verifier");
        
        ImpactRewardMessage storage message = impactRewardMessages[_messageId];
        require(!message.isVerified, "Already verified");
        require(message.verifierRatings[msg.sender] == ImpactLevel(0) || 
                msg.sender != message.verifiers[0], "Already rated");

        message.verifiers.push(msg.sender);
        message.verifierRatings[msg.sender] = _impactRating;

        // If threshold reached, finalize verification and reward
        if (message.verifiers.length >= VERIFICATION_THRESHOLD && !message.isRewarded) {
            // Calculate average rating
            uint256 totalRating = 0;
            for (uint256 i = 0; i < message.verifiers.length; i++) {
                totalRating += uint256(message.verifierRatings[message.verifiers[i]]);
            }
            uint256 averageRating = totalRating / message.verifiers.length;
            
            message.verifiedImpact = ImpactLevel(averageRating);
            message.isVerified = true;
            message.isRewarded = true;

            uint256 rewardAmount = getRewardAmount(message.verifiedImpact);
            
            // Check reward pool and distribute
            if (rewardPool >= rewardAmount) {
                message.rewardAmount = rewardAmount;
                rewardPool -= rewardAmount;
                userTotalRewards[message.creator] += rewardAmount;

                IERC20 cusd = IERC20(CUSD_ADDRESS);
                require(
                    cusd.transfer(message.creator, rewardAmount),
                    "Reward transfer failed"
                );

                emit ImpactVerifiedAndRewarded(
                    _messageId,
                    message.creator,
                    message.verifiedImpact,
                    rewardAmount,
                    block.timestamp
                );
            }
        }
    }

    /**
     * @dev Get impact message details
     */
    function getImpactMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            string memory title,
            string memory description,
            ImpactLevel expectedImpact,
            ImpactLevel verifiedImpact,
            address[] memory recipients,
            uint256 timestamp,
            bool isVerified,
            bool isRewarded,
            uint256 rewardAmount
        )
    {
        ImpactRewardMessage storage message = impactRewardMessages[_messageId];
        return (
            message.id,
            message.creator,
            message.title,
            message.description,
            message.expectedImpact,
            message.verifiedImpact,
            message.recipients,
            message.timestamp,
            message.isVerified,
            message.isRewarded,
            message.rewardAmount
        );
    }

    /**
     * @dev Get user's total rewards
     */
    function getUserTotalRewards(address _user) external view returns (uint256) {
        return userTotalRewards[_user];
    }

    /**
     * @dev Get user's impact message count
     */
    function getUserImpactMessages(address _user) external view returns (uint256) {
        return userImpactMessages[_user];
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Get reward pool balance
     */
    function getRewardPoolBalance() external view returns (uint256) {
        return rewardPool;
    }

    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        uint256 balance = cusd.balanceOf(address(this));
        require(balance > 0, "No balance");

        require(cusd.transfer(owner(), balance), "Withdraw failed");
        rewardPool = 0;
    }
}
