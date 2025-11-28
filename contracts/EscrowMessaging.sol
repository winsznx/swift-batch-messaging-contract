// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title EscrowMessaging
 * @dev A contract with escrowed payments that release upon confirmation
 * @author Swift v2 Team
 */
contract EscrowMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event EscrowMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 escrowAmount,
        uint256 timestamp
    );

    event MessageConfirmed(
        uint256 indexed messageId,
        address indexed recipient,
        uint256 timestamp
    );

    event EscrowReleased(
        uint256 indexed messageId,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    event EscrowRefunded(
        uint256 indexed messageId,
        address indexed sender,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct EscrowMessage {
        uint256 id;
        address sender;
        address recipient;
        string content;
        uint256 escrowAmount;
        uint256 timestamp;
        uint256 expiryTime;
        bool isConfirmed;
        bool isReleased;
        bool isRefunded;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => EscrowMessage) public escrowMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(address => uint256[]) public userReceivedMessages;

    // Constants
    uint256 public constant ESCROW_FEE = 0.000003 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant DEFAULT_EXPIRY_DURATION = 604800; // 7 days

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send a message with escrowed payment
     * @param _recipient Address of the recipient
     * @param _content Message content
     * @param _expiryDuration How long until escrow expires
     */
    function sendEscrowMessage(
        address _recipient,
        string memory _content,
        uint256 _expiryDuration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(msg.value > ESCROW_FEE, "Insufficient payment for escrow");
        
        uint256 escrowAmount = msg.value - ESCROW_FEE;
        uint256 expiry = _expiryDuration > 0 ? _expiryDuration : DEFAULT_EXPIRY_DURATION;
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        EscrowMessage storage message = escrowMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.content = _content;
        message.escrowAmount = escrowAmount;
        message.timestamp = block.timestamp;
        message.expiryTime = block.timestamp + expiry;
        message.isConfirmed = false;
        message.isReleased = false;
        message.isRefunded = false;

        userSentMessages[msg.sender].push(messageId);
        userReceivedMessages[_recipient].push(messageId);

        emit EscrowMessageSent(messageId, msg.sender, _recipient, escrowAmount, block.timestamp);
    }

    /**
     * @dev Confirm message receipt to release escrow
     * @param _messageId ID of the message
     */
    function confirmMessage(uint256 _messageId) 
        external 
        nonReentrant 
    {
        EscrowMessage storage message = escrowMessages[_messageId];
        require(message.recipient == msg.sender, "Only recipient can confirm");
        require(!message.isConfirmed, "Already confirmed");
        require(!message.isReleased, "Already released");
        require(!message.isRefunded, "Already refunded");
        require(block.timestamp <= message.expiryTime, "Escrow expired");

        message.isConfirmed = true;

        emit MessageConfirmed(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Release escrow to recipient after confirmation
     * @param _messageId ID of the message
     */
    function releaseEscrow(uint256 _messageId) 
        external 
        nonReentrant 
    {
        EscrowMessage storage message = escrowMessages[_messageId];
        require(message.isConfirmed, "Not confirmed");
        require(!message.isReleased, "Already released");
        require(!message.isRefunded, "Already refunded");

        message.isReleased = true;

        (bool success, ) = payable(message.recipient).call{value: message.escrowAmount}("");
        require(success, "Escrow release failed");

        emit EscrowReleased(_messageId, message.recipient, message.escrowAmount, block.timestamp);
    }

    /**
     * @dev Refund escrow to sender after expiry
     * @param _messageId ID of the message
     */
    function refundEscrow(uint256 _messageId) 
        external 
        nonReentrant 
    {
        EscrowMessage storage message = escrowMessages[_messageId];
        require(block.timestamp > message.expiryTime, "Not expired yet");
        require(!message.isConfirmed, "Message was confirmed");
        require(!message.isReleased, "Already released");
        require(!message.isRefunded, "Already refunded");

        message.isRefunded = true;

        (bool success, ) = payable(message.sender).call{value: message.escrowAmount}("");
        require(success, "Refund failed");

        emit EscrowRefunded(_messageId, message.sender, message.escrowAmount, block.timestamp);
    }

    /**
     * @dev Get escrow message details
     */
    function getEscrowMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            string memory content,
            uint256 escrowAmount,
            uint256 timestamp,
            uint256 expiryTime,
            bool isConfirmed,
            bool isReleased,
            bool isRefunded
        )
    {
        EscrowMessage storage message = escrowMessages[_messageId];
        require(
            msg.sender == message.sender || msg.sender == message.recipient,
            "Not authorized"
        );
        
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.escrowAmount,
            message.timestamp,
            message.expiryTime,
            message.isConfirmed,
            message.isReleased,
            message.isRefunded
        );
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
