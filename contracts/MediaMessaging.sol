// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MediaMessaging
 * @dev A contract optimized for IPFS/Arweave media URL storage with content hashes
 * @author Swift v2 Team
 */
contract MediaMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum MediaType { IMAGE, VIDEO, AUDIO, DOCUMENT, OTHER }

    // Events
    event MediaMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        string mediaUrl,
        MediaType mediaType,
        uint256 timestamp
    );

    // Structs
    struct MediaMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string mediaUrl; // IPFS or Arweave URL
        bytes32 contentHash; // Hash of media content
        MediaType mediaType;
        string caption;
        uint256 fileSize;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => MediaMessage) public mediaMessages;
    mapping(address => uint256[]) public userSentMessages;
    mapping(bytes32 => bool) public contentHashExists;

    // Constants
    uint256 public constant MEDIA_MESSAGE_FEE = 0.000005 ether;
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_CAPTION_LENGTH = 500;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Send a media message
     * @param _recipients Array of recipient addresses
     * @param _mediaUrl IPFS or Arweave URL
     * @param _contentHash Hash of media content
     * @param _mediaType Type of media
     * @param _caption Optional caption
     * @param _fileSize Size in bytes
     */
    function sendMediaMessage(
        address[] memory _recipients,
        string memory _mediaUrl,
        bytes32 _contentHash,
        MediaType _mediaType,
        string memory _caption,
        uint256 _fileSize
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MEDIA_MESSAGE_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_mediaUrl).length > 0, "Empty media URL");
        require(_contentHash != bytes32(0), "Invalid content hash");
        require(bytes(_caption).length <= MAX_CAPTION_LENGTH, "Caption too long");
        require(_fileSize > 0, "Invalid file size");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        MediaMessage storage message = mediaMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.mediaUrl = _mediaUrl;
        message.contentHash = _contentHash;
        message.mediaType = _mediaType;
        message.caption = _caption;
        message.fileSize = _fileSize;
        message.timestamp = block.timestamp;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        contentHashExists[_contentHash] = true;
        userSentMessages[msg.sender].push(messageId);

        emit MediaMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            _mediaUrl,
            _mediaType,
            block.timestamp
        );
    }

    /**
     * @dev Verify media content hash
     * @param _messageId ID of the message
     * @param _hash Hash to verify
     */
    function verifyContentHash(uint256 _messageId, bytes32 _hash) 
        external 
        view 
        returns (bool)
    {
        return mediaMessages[_messageId].contentHash == _hash;
    }

    /**
     * @dev Get media message details
     */
    function getMediaMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory mediaUrl,
            bytes32 contentHash,
            MediaType mediaType,
            string memory caption,
            uint256 fileSize,
            uint256 timestamp
        )
    {
        MediaMessage storage message = mediaMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.mediaUrl,
            message.contentHash,
            message.mediaType,
            message.caption,
            message.fileSize,
            message.timestamp
        );
    }

    /**
     * @dev Get user's sent messages
     */
    function getUserSentMessages(address _user) external view returns (uint256[] memory) {
        return userSentMessages[_user];
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
