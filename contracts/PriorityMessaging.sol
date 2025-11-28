// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title PriorityMessaging
 * @dev A contract with priority levels and dynamic fee pricing
 * @author Swift v2 Team
 */
contract PriorityMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum Priority { LOW, MEDIUM, HIGH, URGENT }

    // Events
    event PriorityMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        Priority priority,
        uint256 timestamp
    );

    // Structs
    struct PriorityMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        Priority priority;
        uint256 timestamp;
        string messageType;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => PriorityMessage) public priorityMessages;
    mapping(address => uint256[]) public userMessages;

    // Fee structure
    uint256 public constant LOW_PRIORITY_FEE = 0.000002 ether;
    uint256 public constant MEDIUM_PRIORITY_FEE = 0.000005 ether;
    uint256 public constant HIGH_PRIORITY_FEE = 0.00001 ether;
    uint256 public constant URGENT_PRIORITY_FEE = 0.00002 ether;

    uint256 public constant MAX_RECIPIENTS = 1000;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Get fee for priority level
     */
    function getFeeForPriority(Priority _priority) public pure returns (uint256) {
        if (_priority == Priority.LOW) return LOW_PRIORITY_FEE;
        if (_priority == Priority.MEDIUM) return MEDIUM_PRIORITY_FEE;
        if (_priority == Priority.HIGH) return HIGH_PRIORITY_FEE;
        if (_priority == Priority.URGENT) return URGENT_PRIORITY_FEE;
        return MEDIUM_PRIORITY_FEE;
    }

    /**
     * @dev Send a priority message
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _priority Priority level
     * @param _messageType Type of message
     */
    function sendPriorityMessage(
        address[] memory _recipients,
        string memory _content,
        Priority _priority,
        string memory _messageType
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 requiredFee = getFeeForPriority(_priority);
        require(msg.value >= requiredFee, "Insufficient fee for priority level");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        PriorityMessage storage message = priorityMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.priority = _priority;
        message.timestamp = block.timestamp;
        message.messageType = _messageType;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userMessages[msg.sender].push(messageId);

        emit PriorityMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            _priority,
            block.timestamp
        );
    }

    /**
     * @dev Get priority message details
     */
    function getPriorityMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            Priority priority,
            uint256 timestamp,
            string memory messageType
        )
    {
        PriorityMessage storage message = priorityMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.priority,
            message.timestamp,
            message.messageType
        );
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
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
