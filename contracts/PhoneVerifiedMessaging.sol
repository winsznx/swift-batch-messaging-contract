// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title PhoneVerifiedMessaging
 * @dev Phone-verified identity messaging using Celo's attestation service
 * @author Swift v2 Team
 */
contract PhoneVerifiedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event PhoneVerificationSubmitted(
        address indexed userAddress,
        bytes32 indexed phoneHash,
        uint256 timestamp
    );

    event PhoneVerified(
        address indexed userAddress,
        bytes32 indexed phoneHash,
        uint256 timestamp
    );

    event VerifiedMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        bool onlyVerified,
        uint256 timestamp
    );

    // Structs
    struct PhoneVerification {
        address userAddress;
        bytes32 phoneHash;
        uint256 submittedAt;
        bool isVerified;
        address[] attesters;
    }

    struct VerifiedMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        bool onlyVerified; // Only send to verified users
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(address => PhoneVerification) public phoneVerifications;
    mapping(bytes32 => address) public phoneHashToAddress;
    mapping(uint256 => VerifiedMessage) public verifiedMessages;
    mapping(address => uint256[]) public userMessages;
    mapping(address => bool) public approvedAttesters;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant VERIFIED_MESSAGE_FEE = 0.00001 ether;
    uint256 public constant ATTESTATION_THRESHOLD = 3;

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Add approved attester
     */
    function addAttester(address _attester) external onlyOwner {
        require(_attester != address(0), "Invalid attester");
        approvedAttesters[_attester] = true;
    }

    /**
     * @dev Remove attester
     */
    function removeAttester(address _attester) external onlyOwner {
        approvedAttesters[_attester] = false;
    }

    /**
     * @dev Submit phone for verification
     * @param _phoneHash Hash of phone number
     */
    function submitPhoneVerification(bytes32 _phoneHash) 
        external 
    {
        require(_phoneHash != bytes32(0), "Invalid phone hash");
        require(phoneHashToAddress[_phoneHash] == address(0), "Phone already registered");
        require(phoneVerifications[msg.sender].phoneHash == bytes32(0), "Already submitted");
        
        PhoneVerification storage verification = phoneVerifications[msg.sender];
        verification.userAddress = msg.sender;
        verification.phoneHash = _phoneHash;
        verification.submittedAt = block.timestamp;
        verification.isVerified = false;

        phoneHashToAddress[_phoneHash] = msg.sender;

        emit PhoneVerificationSubmitted(msg.sender, _phoneHash, block.timestamp);
    }

    /**
     * @dev Attest phone verification (approved attesters only)
     * @param _userAddress Address to attest
     */
    function attestPhoneVerification(address _userAddress) 
        external 
    {
        require(approvedAttesters[msg.sender], "Not an approved attester");
        
        PhoneVerification storage verification = phoneVerifications[_userAddress];
        require(verification.phoneHash != bytes32(0), "No verification submitted");
        require(!verification.isVerified, "Already verified");

        // Check if attester already attested
        for (uint256 i = 0; i < verification.attesters.length; i++) {
            require(verification.attesters[i] != msg.sender, "Already attested");
        }

        verification.attesters.push(msg.sender);

        // If threshold reached, mark as verified
        if (verification.attesters.length >= ATTESTATION_THRESHOLD) {
            verification.isVerified = true;
            emit PhoneVerified(_userAddress, verification.phoneHash, block.timestamp);
        }
    }

    /**
     * @dev Send verified message
     * @param _recipients Array of recipients
     * @param _content Message content
     * @param _onlyVerified Only send to verified users
     */
    function sendVerifiedMessage(
        address[] memory _recipients,
        string memory _content,
        bool _onlyVerified
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= VERIFIED_MESSAGE_FEE, "Insufficient fee");
        require(phoneVerifications[msg.sender].isVerified, "Sender not verified");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        VerifiedMessage storage message = verifiedMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.onlyVerified = _onlyVerified;
        message.timestamp = block.timestamp;

        for (uint256 i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];
            
            if (recipient == address(0) || recipient == msg.sender) {
                continue;
            }

            // If onlyVerified, skip unverified recipients
            if (_onlyVerified && !phoneVerifications[recipient].isVerified) {
                continue;
            }

            message.recipients.push(recipient);
        }

        require(message.recipients.length > 0, "No valid recipients");

        userMessages[msg.sender].push(messageId);

        emit VerifiedMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            _onlyVerified,
            block.timestamp
        );
    }

    /**
     * @dev Check if user is verified
     */
    function isUserVerified(address _user) external view returns (bool) {
        return phoneVerifications[_user].isVerified;
    }

    /**
     * @dev Get phone verification details
     */
    function getPhoneVerification(address _user) 
        external 
        view 
        returns (
            address userAddress,
            bytes32 phoneHash,
            uint256 submittedAt,
            bool isVerified,
            uint256 attesterCount
        )
    {
        PhoneVerification storage verification = phoneVerifications[_user];
        return (
            verification.userAddress,
            verification.phoneHash,
            verification.submittedAt,
            verification.isVerified,
            verification.attesters.length
        );
    }

    /**
     * @dev Get verification attesters
     */
    function getVerificationAttesters(address _user) 
        external 
        view 
        returns (address[] memory)
    {
        return phoneVerifications[_user].attesters;
    }

    /**
     * @dev Get verified message details
     */
    function getVerifiedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            bool onlyVerified,
            uint256 timestamp
        )
    {
        VerifiedMessage storage message = verifiedMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.onlyVerified,
            message.timestamp
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
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
