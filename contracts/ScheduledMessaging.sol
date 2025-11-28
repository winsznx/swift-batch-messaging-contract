// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ScheduledMessaging
 * @dev A contract for scheduling messages to be sent at future timestamps
 * @author Swift v2 Team
 */
contract ScheduledMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MessageScheduled(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        uint256 scheduledTime,
        uint256 timestamp
    );

    event MessageExecuted(
        uint256 indexed messageId,
        address indexed executor,
        uint256 timestamp
    );

    event MessageCancelled(
        uint256 indexed messageId,
        address indexed sender,
        uint256 timestamp
    );

    // Structs
    struct ScheduledMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        uint256 scheduledTime;
        uint256 createdAt;
        string messageType;
        bool isExecuted;
        bool isCancelled;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => ScheduledMessage) public scheduledMessages;
    mapping(address => uint256[]) public userScheduledMessages;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 1000;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant SCHEDULING_FEE = 0.000005 ether;
    uint256 public constant MIN_SCHEDULE_DELAY = 60; // 1 minute

    // Modifiers
    modifier validRecipients(address[] memory _recipients) {
        require(_recipients.length > 0, "No recipients provided");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        _;
    }

    modifier validMessageLength(string memory _content) {
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Message too long");
        require(bytes(_content).length > 0, "Message cannot be empty");
        _;
    }

    modifier messageExists(uint256 _messageId) {
        require(_messageId > 0 && _messageId <= _messageIdCounter.current(), "Message does not exist");
        _;
    }

    modifier onlyMessageSender(uint256 _messageId) {
        require(scheduledMessages[_messageId].sender == msg.sender, "Only sender can perform this action");
        _;
    }

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Schedule a message for future delivery
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _scheduledTime Unix timestamp when message should be delivered
     * @param _messageType Type of message
     */
    function scheduleMessage(
        address[] memory _recipients,
        string memory _content,
        uint256 _scheduledTime,
        string memory _messageType
    ) 
        external 
        payable 
        nonReentrant 
        validRecipients(_recipients)
        validMessageLength(_content)
    {
        require(msg.value >= SCHEDULING_FEE, "Insufficient fee for scheduling");
        require(_scheduledTime > block.timestamp + MIN_SCHEDULE_DELAY, "Schedule time too soon");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        ScheduledMessage storage message = scheduledMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.scheduledTime = _scheduledTime;
        message.createdAt = block.timestamp;
        message.messageType = _messageType;
        message.isExecuted = false;
        message.isCancelled = false;

        // Add recipients
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userScheduledMessages[msg.sender].push(messageId);

        emit MessageScheduled(
            messageId,
            msg.sender,
            message.recipients,
            _scheduledTime,
            block.timestamp
        );
    }

    /**
     * @dev Execute a scheduled message when time has arrived
     * @param _messageId ID of the scheduled message
     */
    function executeScheduledMessage(uint256 _messageId) 
        external 
        nonReentrant 
        messageExists(_messageId)
    {
        ScheduledMessage storage message = scheduledMessages[_messageId];
        require(!message.isExecuted, "Message already executed");
        require(!message.isCancelled, "Message was cancelled");
        require(block.timestamp >= message.scheduledTime, "Too early to execute");

        message.isExecuted = true;

        emit MessageExecuted(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Cancel a scheduled message before execution
     * @param _messageId ID of the scheduled message
     */
    function cancelScheduledMessage(uint256 _messageId) 
        external 
        nonReentrant 
        messageExists(_messageId)
        onlyMessageSender(_messageId)
    {
        ScheduledMessage storage message = scheduledMessages[_messageId];
        require(!message.isExecuted, "Message already executed");
        require(!message.isCancelled, "Message already cancelled");

        message.isCancelled = true;

        emit MessageCancelled(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get scheduled message details
     * @param _messageId ID of the message
     */
    function getScheduledMessage(uint256 _messageId) 
        external 
        view 
        messageExists(_messageId)
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 scheduledTime,
            uint256 createdAt,
            string memory messageType,
            bool isExecuted,
            bool isCancelled
        )
    {
        ScheduledMessage storage message = scheduledMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.scheduledTime,
            message.createdAt,
            message.messageType,
            message.isExecuted,
            message.isCancelled
        );
    }

    /**
     * @dev Get user's scheduled messages
     * @param _user Address of the user
     */
    function getUserScheduledMessages(address _user) external view returns (uint256[] memory) {
        return userScheduledMessages[_user];
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
