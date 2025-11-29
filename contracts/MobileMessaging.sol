// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MobileMessaging
 * @dev Mobile-optimized messaging with phone number mapping
 * @author Swift v2 Team
 */
contract MobileMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event PhoneNumberRegistered(
        address indexed userAddress,
        bytes32 indexed phoneHash,
        uint256 timestamp
    );

    event MobileMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        bytes32[] recipientPhoneHashes,
        uint256 timestamp
    );

    // Structs
    struct MobileMessage {
        uint256 id;
        address sender;
        bytes32[] recipientPhoneHashes; // Hashed phone numbers for privacy
        address[] recipientAddresses;
        string content;
        uint256 timestamp;
        bool isUrgent;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => MobileMessage) public mobileMessages;
    mapping(bytes32 => address) public phoneToAddress; // phoneHash => address
    mapping(address => bytes32) public addressToPhone; // address => phoneHash
    mapping(address => uint256[]) public userMessages;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 100; // Lower for mobile optimization
    uint256 public constant MAX_MESSAGE_LENGTH = 500; // Shorter for mobile
    uint256 public constant MOBILE_MESSAGE_FEE = 0.00001 ether;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Register phone number (hashed for privacy)
     * @param _phoneHash Hash of phone number (keccak256(phoneNumber))
     */
    function registerPhoneNumber(bytes32 _phoneHash) 
        external 
    {
        require(_phoneHash != bytes32(0), "Invalid phone hash");
        require(phoneToAddress[_phoneHash] == address(0), "Phone already registered");
        
        phoneToAddress[_phoneHash] = msg.sender;
        addressToPhone[msg.sender] = _phoneHash;

        emit PhoneNumberRegistered(msg.sender, _phoneHash, block.timestamp);
    }

    /**
     * @dev Send mobile-optimized message to phone numbers
     * @param _recipientPhoneHashes Array of hashed phone numbers
     * @param _content Message content (kept short for mobile)
     * @param _isUrgent Mark as urgent for priority delivery
     */
    function sendMobileMessage(
        bytes32[] memory _recipientPhoneHashes,
        string memory _content,
        bool _isUrgent
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MOBILE_MESSAGE_FEE, "Insufficient fee");
        require(_recipientPhoneHashes.length > 0, "No recipients");
        require(_recipientPhoneHashes.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        MobileMessage storage message = mobileMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.isUrgent = _isUrgent;

        // Resolve phone hashes to addresses
        for (uint256 i = 0; i < _recipientPhoneHashes.length; i++) {
            bytes32 phoneHash = _recipientPhoneHashes[i];
            message.recipientPhoneHashes.push(phoneHash);
            
            address recipientAddress = phoneToAddress[phoneHash];
            if (recipientAddress != address(0) && recipientAddress != msg.sender) {
                message.recipientAddresses.push(recipientAddress);
            }
        }

        require(message.recipientPhoneHashes.length > 0, "No valid recipients");

        userMessages[msg.sender].push(messageId);

        emit MobileMessageSent(
            messageId,
            msg.sender,
            message.recipientPhoneHashes,
            block.timestamp
        );
    }

    /**
     * @dev Get mobile message details
     */
    function getMobileMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            bytes32[] memory recipientPhoneHashes,
            address[] memory recipientAddresses,
            string memory content,
            uint256 timestamp,
            bool isUrgent
        )
    {
        MobileMessage storage message = mobileMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipientPhoneHashes,
            message.recipientAddresses,
            message.content,
            message.timestamp,
            message.isUrgent
        );
    }

    /**
     * @dev Check if phone number is registered
     */
    function isPhoneRegistered(bytes32 _phoneHash) external view returns (bool) {
        return phoneToAddress[_phoneHash] != address(0);
    }

    /**
     * @dev Get address for phone hash
     */
    function getAddressForPhone(bytes32 _phoneHash) external view returns (address) {
        return phoneToAddress[_phoneHash];
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
