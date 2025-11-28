// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ExpiringMessaging
 * @dev A contract with self-destructing messages that expire after a set duration
 * @author Swift v2 Team
 */
contract ExpiringMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ExpiringMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 expiresAt,
        uint256 timestamp
    );

    event MessageRead(
        uint256 indexed messageId,
        address indexed recipient,
        uint256 timestamp
    );

    event MessageExpired(
        uint256 indexed messageId,
        uint256 timestamp
    );

    // Structs
    struct ExpiringMessage {
        uint256 id;
        address sender;
        address recipient;
        string content;
        uint256 timestamp;
        uint256 expiresAt;
        bool isRead;
        bool isExpired;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => ExpiringMessage) public expiringMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(address => uint256[]) public userReceivedMessages;

    // Constants
    uint256 public constant EXPIRING_MESSAGE_FEE = 0.000004 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_EXPIRY_DURATION = 60; // 1 minute
    uint256 public constant MAX_EXPIRY_DURATION = 2592000; // 30 days

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send an expiring message
     * @param _recipient Address of the recipient
     * @param _content Message content
     * @param _expiryDuration Duration in seconds until message expires
     */
    function sendExpiringMessage(
        address _recipient,
        string memory _content,
        uint256 _expiryDuration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= EXPIRING_MESSAGE_FEE, "Insufficient fee");
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_expiryDuration >= MIN_EXPIRY_DURATION, "Expiry duration too short");
        require(_expiryDuration <= MAX_EXPIRY_DURATION, "Expiry duration too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        uint256 expiresAt = block.timestamp + _expiryDuration;

        ExpiringMessage storage message = expiringMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.expiresAt = expiresAt;
        message.isRead = false;
        message.isExpired = false;

        userSentMessages[msg.sender].push(messageId);
        userReceivedMessages[_recipient].push(messageId);

        emit ExpiringMessageSent(messageId, msg.sender, _recipient, expiresAt, block.timestamp);
    }

    /**
     * @dev Read a message (recipient only)
     * @param _messageId ID of the message
     */
    function readMessage(uint256 _messageId) 
        external 
        nonReentrant 
    {
        ExpiringMessage storage message = expiringMessages[_messageId];
        require(message.recipient == msg.sender, "Only recipient can read");
        require(!message.isExpired, "Message has expired");
        require(block.timestamp < message.expiresAt, "Message has expired");
        
        if (!message.isRead) {
            message.isRead = true;
            emit MessageRead(_messageId, msg.sender, block.timestamp);
        }
    }

    /**
     * @dev Mark message as expired (anyone can call after expiry)
     * @param _messageId ID of the message
     */
    function expireMessage(uint256 _messageId) 
        external 
        nonReentrant 
    {
        ExpiringMessage storage message = expiringMessages[_messageId];
        require(!message.isExpired, "Already expired");
        require(block.timestamp >= message.expiresAt, "Not expired yet");

        message.isExpired = true;
        // Clear content to save gas
        delete message.content;

        emit MessageExpired(_messageId, block.timestamp);
    }

    /**
     * @dev Get expiring message details
     */
    function getExpiringMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            string memory content,
            uint256 timestamp,
            uint256 expiresAt,
            bool isRead,
            bool isExpired
        )
    {
        ExpiringMessage storage message = expiringMessages[_messageId];
        require(
            msg.sender == message.sender || msg.sender == message.recipient,
            "Not authorized"
        );
        require(!message.isExpired, "Message has expired");
        require(block.timestamp < message.expiresAt, "Message has expired");
        
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.timestamp,
            message.expiresAt,
            message.isRead,
            message.isExpired
        );
    }

    /**
     * @dev Check if message is expired
     */
    function isMessageExpired(uint256 _messageId) 
        external 
        view 
        returns (bool)
    {
        ExpiringMessage storage message = expiringMessages[_messageId];
        return message.isExpired || block.timestamp >= message.expiresAt;
    }

    /**
     * @dev Get user's sent messages
     */
    function getUserSentMessages(address _user) external view returns (uint256[] memory) {
        return userSentMessages[_user];
    }

    /**
     * @dev Get user's received messages
     */
    function getUserReceivedMessages(address _user) external view returns (uint256[] memory) {
        return userReceivedMessages[_user];
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
