// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ReputationMessaging
 * @dev Reputation-based messaging with rating and trust scoring
 * @author Swift v2 Team
 */
contract ReputationMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 timestamp
    );

    event MessageRated(
        uint256 indexed messageId,
        address indexed rater,
        uint8 rating,
        uint256 timestamp
    );

    event ReputationUpdated(
        address indexed user,
        uint256 newScore,
        uint256 timestamp
    );

    event SpamReported(
        uint256 indexed messageId,
        address indexed reporter,
        uint256 timestamp
    );

    // Structs
    struct Message {
        uint256 id;
        address sender;
        address recipient;
        string content;
        uint256 timestamp;
        uint8 averageRating;
        uint256 totalRatings;
        mapping(address => uint8) ratings;
        mapping(address => bool) hasRated;
        uint256 spamReports;
        bool isSpam;
    }

    struct UserReputation {
        uint256 score;
        uint256 messagesSent;
        uint256 messagesReceived;
        uint256 totalRatings;
        uint256 averageRating;
        uint256 spamReports;
        bool isBanned;
        uint256 lastActive;
    }

    struct ReputationTier {
        string name;
        uint256 minScore;
        uint256 maxScore;
        uint256 messageFee;
        uint256 dailyLimit;
        bool canBroadcast;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => Message) public messages;
    mapping(address => UserReputation) public userReputations;
    mapping(address => uint256[]) public sentMessages;
    mapping(address => uint256[]) public receivedMessages;
    mapping(address => mapping(uint256 => uint256)) public dailyMessageCount;
    
    ReputationTier[] public reputationTiers;

    // Constants
    uint256 public constant INITIAL_REPUTATION = 50;
    uint256 public constant MIN_REPUTATION = 0;
    uint256 public constant MAX_REPUTATION = 100;
    uint256 public constant SPAM_THRESHOLD = 3;
    uint256 public constant BASE_MESSAGE_FEE = 0.000001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _messageIdCounter.increment();
        _initializeReputationTiers();
    }

    /**
     * @dev Initialize reputation tiers
     */
    function _initializeReputationTiers() private {
        // Newcomer
        reputationTiers.push(ReputationTier({
            name: "Newcomer",
            minScore: 0,
            maxScore: 25,
            messageFee: BASE_MESSAGE_FEE * 5,
            dailyLimit: 10,
            canBroadcast: false
        }));

        // Regular
        reputationTiers.push(ReputationTier({
            name: "Regular",
            minScore: 26,
            maxScore: 50,
            messageFee: BASE_MESSAGE_FEE * 3,
            dailyLimit: 50,
            canBroadcast: false
        }));

        // Trusted
        reputationTiers.push(ReputationTier({
            name: "Trusted",
            minScore: 51,
            maxScore: 75,
            messageFee: BASE_MESSAGE_FEE * 2,
            dailyLimit: 100,
            canBroadcast: true
        }));

        // Elite
        reputationTiers.push(ReputationTier({
            name: "Elite",
            minScore: 76,
            maxScore: 100,
            messageFee: BASE_MESSAGE_FEE,
            dailyLimit: 500,
            canBroadcast: true
        }));
    }

    /**
     * @dev Get user's reputation tier
     */
    function getUserTier(address _user) public view returns (uint256) {
        uint256 score = userReputations[_user].score;
        
        for (uint256 i = reputationTiers.length; i > 0; i--) {
            if (score >= reputationTiers[i - 1].minScore && 
                score <= reputationTiers[i - 1].maxScore) {
                return i - 1;
            }
        }
        
        return 0;
    }

    /**
     * @dev Initialize new user reputation
     */
    function _initializeUserReputation(address _user) private {
        if (userReputations[_user].lastActive == 0) {
            userReputations[_user].score = INITIAL_REPUTATION;
            userReputations[_user].lastActive = block.timestamp;
        }
    }

    /**
     * @dev Send reputation-based message
     */
    function sendMessage(
        address _recipient,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot message yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        _initializeUserReputation(msg.sender);
        _initializeUserReputation(_recipient);

        UserReputation storage senderRep = userReputations[msg.sender];
        require(!senderRep.isBanned, "Sender is banned");

        // Check reputation tier limits
        uint256 tierIndex = getUserTier(msg.sender);
        ReputationTier memory tier = reputationTiers[tierIndex];

        // Check daily limit
        uint256 today = block.timestamp / 1 days;
        require(
            dailyMessageCount[msg.sender][today] < tier.dailyLimit,
            "Daily limit reached"
        );

        // Check fee
        require(msg.value >= tier.messageFee, "Insufficient fee");

        // Create message
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        Message storage message = messages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.content = _content;
        message.timestamp = block.timestamp;

        sentMessages[msg.sender].push(messageId);
        receivedMessages[_recipient].push(messageId);
        dailyMessageCount[msg.sender][today]++;

        senderRep.messagesSent++;
        userReputations[_recipient].messagesReceived++;
        senderRep.lastActive = block.timestamp;

        emit MessageSent(messageId, msg.sender, _recipient, block.timestamp);

        return messageId;
    }

    /**
     * @dev Rate a received message
     */
    function rateMessage(
        uint256 _messageId,
        uint8 _rating
    ) 
        external 
        nonReentrant 
    {
        require(_rating >= 1 && _rating <= 5, "Rating must be 1-5");
        
        Message storage message = messages[_messageId];
        require(message.id != 0, "Message doesn't exist");
        require(message.recipient == msg.sender, "Only recipient can rate");
        require(!message.hasRated[msg.sender], "Already rated");
        require(!message.isSpam, "Cannot rate spam");

        message.ratings[msg.sender] = _rating;
        message.hasRated[msg.sender] = true;
        message.totalRatings++;

        // Update average rating
        uint256 totalScore = message.averageRating * (message.totalRatings - 1);
        message.averageRating = uint8((totalScore + _rating) / message.totalRatings);

        // Update sender's reputation
        _updateReputation(message.sender, _rating);

        emit MessageRated(_messageId, msg.sender, _rating, block.timestamp);
    }

    /**
     * @dev Update user reputation based on rating
     */
    function _updateReputation(address _user, uint8 _rating) private {
        UserReputation storage rep = userReputations[_user];
        rep.totalRatings++;

        // Calculate new average
        uint256 totalScore = rep.averageRating * (rep.totalRatings - 1);
        rep.averageRating = (totalScore + _rating) / rep.totalRatings;

        // Update reputation score based on average rating
        // Rating 5 = +2 points, 4 = +1, 3 = 0, 2 = -1, 1 = -2
        int256 change = int256(uint256(_rating)) - 3;
        
        if (change > 0) {
            if (rep.score + uint256(change) <= MAX_REPUTATION) {
                rep.score += uint256(change);
            } else {
                rep.score = MAX_REPUTATION;
            }
        } else if (change < 0) {
            uint256 decrease = uint256(-change);
            if (rep.score >= decrease) {
                rep.score -= decrease;
            } else {
                rep.score = MIN_REPUTATION;
            }
        }

        emit ReputationUpdated(_user, rep.score, block.timestamp);
    }

    /**
     * @dev Report message as spam
     */
    function reportSpam(uint256 _messageId) 
        external 
        nonReentrant 
    {
        Message storage message = messages[_messageId];
        require(message.id != 0, "Message doesn't exist");
        require(message.recipient == msg.sender, "Only recipient can report");
        require(!message.isSpam, "Already marked as spam");

        message.spamReports++;

        if (message.spamReports >= SPAM_THRESHOLD) {
            message.isSpam = true;
            
            // Penalize sender's reputation
            UserReputation storage senderRep = userReputations[message.sender];
            senderRep.spamReports++;
            
            if (senderRep.score >= 10) {
                senderRep.score -= 10;
            } else {
                senderRep.score = 0;
            }

            // Auto-ban if too many spam reports
            if (senderRep.spamReports >= 10) {
                senderRep.isBanned = true;
            }

            emit ReputationUpdated(message.sender, senderRep.score, block.timestamp);
        }

        emit SpamReported(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get message details
     */
    function getMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            string memory content,
            uint256 timestamp,
            uint8 averageRating,
            uint256 totalRatings,
            uint256 spamReports,
            bool isSpam
        )
    {
        Message storage message = messages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.timestamp,
            message.averageRating,
            message.totalRatings,
            message.spamReports,
            message.isSpam
        );
    }

    /**
     * @dev Get user reputation details
     */
    function getUserReputation(address _user) 
        external 
        view 
        returns (
            uint256 score,
            uint256 messagesSent,
            uint256 messagesReceived,
            uint256 totalRatings,
            uint256 averageRating,
            uint256 spamReports,
            bool isBanned,
            string memory tierName
        )
    {
        UserReputation storage rep = userReputations[_user];
        uint256 tierIndex = getUserTier(_user);
        
        return (
            rep.score,
            rep.messagesSent,
            rep.messagesReceived,
            rep.totalRatings,
            rep.averageRating,
            rep.spamReports,
            rep.isBanned,
            reputationTiers[tierIndex].name
        );
    }

    /**
     * @dev Get sent messages
     */
    function getSentMessages(address _user) external view returns (uint256[] memory) {
        return sentMessages[_user];
    }

    /**
     * @dev Get received messages
     */
    function getReceivedMessages(address _user) external view returns (uint256[] memory) {
        return receivedMessages[_user];
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
