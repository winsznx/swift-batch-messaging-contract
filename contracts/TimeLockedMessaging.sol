// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title TimeLockedMessaging
 * @dev Time-locked messages with delayed content reveal
 * @author Swift v2 Team
 */
contract TimeLockedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event TimeLockedMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 unlockTime,
        uint256 timestamp
    );

    event MessageUnlocked(
        uint256 indexed messageId,
        address indexed unlocker,
        uint256 timestamp
    );

    // Structs
    struct TimeLockedMessage {
        uint256 id;
        address sender;
        address recipient;
        bytes32 contentHash; // Hash of encrypted content
        string encryptedContent;
        uint256 createdAt;
        uint256 unlockTime;
        bool isUnlocked;
        string revealedContent;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => TimeLockedMessage) public timeLockedMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(address => uint256[]) public userReceivedMessages;

    // Constants
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_LOCK_TIME = 60; // 1 minute
    uint256 public constant MAX_LOCK_TIME = 31536000; // 1 year
    uint256 public constant TIME_LOCK_FEE = 0.000005 ether;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send time-locked message
     * @param _recipient Recipient address
     * @param _encryptedContent Encrypted content
     * @param _contentHash Hash of original content
     * @param _lockDuration Lock duration in seconds
     */
    function sendTimeLockedMessage(
        address _recipient,
        string memory _encryptedContent,
        bytes32 _contentHash,
        uint256 _lockDuration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= TIME_LOCK_FEE, "Insufficient fee");
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(bytes(_encryptedContent).length > 0, "Empty content");
        require(bytes(_encryptedContent).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_contentHash != bytes32(0), "Invalid content hash");
        require(_lockDuration >= MIN_LOCK_TIME, "Lock time too short");
        require(_lockDuration <= MAX_LOCK_TIME, "Lock time too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        uint256 unlockTime = block.timestamp + _lockDuration;

        TimeLockedMessage storage message = timeLockedMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.recipient = _recipient;
        message.contentHash = _contentHash;
        message.encryptedContent = _encryptedContent;
        message.createdAt = block.timestamp;
        message.unlockTime = unlockTime;
        message.isUnlocked = false;

        userSentMessages[msg.sender].push(messageId);
        userReceivedMessages[_recipient].push(messageId);

        emit TimeLockedMessageSent(
            messageId,
            msg.sender,
            _recipient,
            unlockTime,
            block.timestamp
        );
    }

    /**
     * @dev Unlock and reveal message after time lock expires
     * @param _messageId Message ID
     * @param _revealedContent Revealed content
     */
    function unlockMessage(uint256 _messageId, string memory _revealedContent) 
        external 
        nonReentrant 
    {
        TimeLockedMessage storage message = timeLockedMessages[_messageId];
        require(
            msg.sender == message.sender || msg.sender == message.recipient,
            "Not authorized"
        );
        require(!message.isUnlocked, "Already unlocked");
        require(block.timestamp >= message.unlockTime, "Still locked");
        require(bytes(_revealedContent).length > 0, "Empty revealed content");

        // Verify content matches hash
        bytes32 revealedHash = keccak256(abi.encodePacked(_revealedContent));
        require(revealedHash == message.contentHash, "Content hash mismatch");

        message.isUnlocked = true;
        message.revealedContent = _revealedContent;

        emit MessageUnlocked(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Early unlock (sender only)
     * @param _messageId Message ID
     * @param _revealedContent Revealed content
     */
    function earlyUnlock(uint256 _messageId, string memory _revealedContent) 
        external 
        nonReentrant 
    {
        TimeLockedMessage storage message = timeLockedMessages[_messageId];
        require(msg.sender == message.sender, "Only sender can early unlock");
        require(!message.isUnlocked, "Already unlocked");
        require(bytes(_revealedContent).length > 0, "Empty revealed content");

        // Verify content matches hash
        bytes32 revealedHash = keccak256(abi.encodePacked(_revealedContent));
        require(revealedHash == message.contentHash, "Content hash mismatch");

        message.isUnlocked = true;
        message.revealedContent = _revealedContent;
        message.unlockTime = block.timestamp; // Update unlock time to now

        emit MessageUnlocked(_messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get time-locked message details
     */
    function getTimeLockedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            bytes32 contentHash,
            string memory encryptedContent,
            uint256 createdAt,
            uint256 unlockTime,
            bool isUnlocked,
            string memory revealedContent
        )
    {
        TimeLockedMessage storage message = timeLockedMessages[_messageId];
        require(
            msg.sender == message.sender || 
            msg.sender == message.recipient ||
            msg.sender == owner(),
            "Not authorized to view"
        );
        
        return (
            message.id,
            message.sender,
            message.recipient,
            message.contentHash,
            message.encryptedContent,
            message.createdAt,
            message.unlockTime,
            message.isUnlocked,
            message.revealedContent
        );
    }

    /**
     * @dev Check if message is unlocked
     */
    function isMessageUnlocked(uint256 _messageId) 
        external 
        view 
        returns (bool)
    {
        return timeLockedMessages[_messageId].isUnlocked;
    }

    /**
     * @dev Get time remaining until unlock
     */
    function getTimeRemaining(uint256 _messageId) 
        external 
        view 
        returns (uint256)
    {
        TimeLockedMessage storage message = timeLockedMessages[_messageId];
        
        if (message.isUnlocked) {
            return 0;
        }
        
        if (block.timestamp >= message.unlockTime) {
            return 0;
        }
        
        return message.unlockTime - block.timestamp;
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
     * @dev Verify content hash
     * @param _content Content to hash
     * @param _expectedHash Expected hash
     */
    function verifyContentHash(string memory _content, bytes32 _expectedHash) 
        external 
        pure 
        returns (bool)
    {
        return keccak256(abi.encodePacked(_content)) == _expectedHash;
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
