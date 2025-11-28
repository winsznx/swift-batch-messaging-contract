// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ModerationMessaging
 * @dev A contract with moderator roles that can filter/block inappropriate content
 * @author Swift v2 Team
 */
contract ModerationMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ModeratorAdded(address indexed moderator, uint256 timestamp);
    event ModeratorRemoved(address indexed moderator, uint256 timestamp);
    
    event MessageSubmitted(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        uint256 timestamp
    );

    event MessageApproved(
        uint256 indexed messageId,
        address indexed moderator,
        uint256 timestamp
    );

    event MessageBlocked(
        uint256 indexed messageId,
        address indexed moderator,
        string reason,
        uint256 timestamp
    );

    // Structs
    struct ModeratedMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        uint256 timestamp;
        bool isApproved;
        bool isBlocked;
        address moderatedBy;
        string blockReason;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => ModeratedMessage) public moderatedMessages;
    mapping(address => bool) public isModerator;
    mapping(address => uint256[]) public userMessages;
    mapping(address => uint256) public userBlockedCount;

    // Constants
    uint256 public constant MODERATED_MESSAGE_FEE = 0.000003 ether;
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Add a moderator
     * @param _moderator Address to add as moderator
     */
    function addModerator(address _moderator) 
        external 
        onlyOwner 
    {
        require(_moderator != address(0), "Invalid address");
        require(!isModerator[_moderator], "Already a moderator");
        
        isModerator[_moderator] = true;
        emit ModeratorAdded(_moderator, block.timestamp);
    }

    /**
     * @dev Remove a moderator
     * @param _moderator Address to remove
     */
    function removeModerator(address _moderator) 
        external 
        onlyOwner 
    {
        require(isModerator[_moderator], "Not a moderator");
        
        isModerator[_moderator] = false;
        emit ModeratorRemoved(_moderator, block.timestamp);
    }

    /**
     * @dev Submit a message for moderation
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     */
    function submitMessage(
        address[] memory _recipients,
        string memory _content
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MODERATED_MESSAGE_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        ModeratedMessage storage message = moderatedMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.isApproved = false;
        message.isBlocked = false;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userMessages[msg.sender].push(messageId);

        emit MessageSubmitted(messageId, msg.sender, message.recipients, block.timestamp);
    }

    /**
     * @dev Approve a message (moderator only)
     * @param _messageId ID of the message
     */
    function approveMessage(uint256 _messageId) 
        external 
        nonReentrant 
    {
        require(isModerator[msg.sender], "Only moderators can approve");
        
        ModeratedMessage storage message = moderatedMessages[_messageId];
        require(!message.isApproved, "Already approved");
        require(!message.isBlocked, "Message is blocked");

        message.isApproved = true;
        message.moderatedBy = msg.sender;

        emit MessageApproved(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Block a message (moderator only)
     * @param _messageId ID of the message
     * @param _reason Reason for blocking
     */
    function blockMessage(uint256 _messageId, string memory _reason) 
        external 
        nonReentrant 
    {
        require(isModerator[msg.sender], "Only moderators can block");
        
        ModeratedMessage storage message = moderatedMessages[_messageId];
        require(!message.isApproved, "Already approved");
        require(!message.isBlocked, "Already blocked");

        message.isBlocked = true;
        message.moderatedBy = msg.sender;
        message.blockReason = _reason;

        userBlockedCount[message.sender]++;

        emit MessageBlocked(_messageId, msg.sender, _reason, block.timestamp);
    }

    /**
     * @dev Get moderated message details
     */
    function getModeratedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 timestamp,
            bool isApproved,
            bool isBlocked,
            address moderatedBy,
            string memory blockReason
        )
    {
        ModeratedMessage storage message = moderatedMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.timestamp,
            message.isApproved,
            message.isBlocked,
            message.moderatedBy,
            message.blockReason
        );
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Get user's blocked count
     */
    function getUserBlockedCount(address _user) external view returns (uint256) {
        return userBlockedCount[_user];
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
