// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title IdentityVerifiedMessaging
 * @dev KYC/identity-verified messaging with trust levels and verification badges
 * @author Swift v2 Team
 */
contract IdentityVerifiedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event UserRegistered(
        address indexed user,
        uint256 timestamp
    );

    event VerificationSubmitted(
        address indexed user,
        VerificationLevel level,
        uint256 timestamp
    );

    event VerificationApproved(
        address indexed user,
        VerificationLevel level,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address indexed recipient,
        uint256 timestamp
    );

    event TrustConnectionCreated(
        address indexed user1,
        address indexed user2,
        uint256 timestamp
    );

    // Enums
    enum VerificationLevel { None, Basic, Advanced, Premium }
    enum TrustLevel { Unknown, Trusted, Verified, Premium }

    // Structs
    struct User {
        address wallet;
        string username;
        VerificationLevel verificationLevel;
        uint256 verifiedAt;
        bool isActive;
        uint256 registeredAt;
        uint256 messagesSent;
        uint256 messagesReceived;
        uint256 trustScore;
        string profileHash;
    }

    struct VerificationRequest {
        address user;
        VerificationLevel requestedLevel;
        string documentHash;
        uint256 submittedAt;
        bool isApproved;
        bool isRejected;
        string rejectionReason;
    }

    struct Message {
        uint256 id;
        address sender;
        address recipient;
        string content;
        uint256 timestamp;
        bool requiresVerification;
        VerificationLevel minVerificationLevel;
        bool isEncrypted;
    }

    struct TrustConnection {
        address user1;
        address user2;
        TrustLevel level;
        uint256 createdAt;
        string note;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    Counters.Counter private _verificationIdCounter;
    
    mapping(address => User) public users;
    mapping(address => VerificationRequest) public verificationRequests;
    mapping(uint256 => Message) public messages;
    mapping(address => uint256[]) public sentMessages;
    mapping(address => uint256[]) public receivedMessages;
    mapping(address => mapping(address => TrustConnection)) public trustConnections;
    mapping(address => address[]) public trustedUsers;
    mapping(address => mapping(VerificationLevel => bool)) public hasVerificationLevel;
    
    address[] public verifiers;
    mapping(address => bool) public isVerifier;

    // Constants
    uint256 public constant MAX_USERNAME_LENGTH = 50;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant VERIFICATION_FEE_BASIC = 0.001 ether;
    uint256 public constant VERIFICATION_FEE_ADVANCED = 0.005 ether;
    uint256 public constant VERIFICATION_FEE_PREMIUM = 0.01 ether;
    uint256 public constant MESSAGE_FEE_VERIFIED = 0.000001 ether;

    constructor() {
        _messageIdCounter.increment();
        _verificationIdCounter.increment();
        
        // Owner is default verifier
        verifiers.push(msg.sender);
        isVerifier[msg.sender] = true;
    }

    /**
     * @dev Register new user
     */
    function registerUser(string memory _username) 
        external 
        nonReentrant 
    {
        require(!users[msg.sender].isActive, "Already registered");
        require(bytes(_username).length > 0 && bytes(_username).length <= MAX_USERNAME_LENGTH, "Invalid username");

        users[msg.sender] = User({
            wallet: msg.sender,
            username: _username,
            verificationLevel: VerificationLevel.None,
            verifiedAt: 0,
            isActive: true,
            registeredAt: block.timestamp,
            messagesSent: 0,
            messagesReceived: 0,
            trustScore: 0,
            profileHash: ""
        });

        emit UserRegistered(msg.sender, block.timestamp);
    }

    /**
     * @dev Submit verification request
     */
    function submitVerification(
        VerificationLevel _level,
        string memory _documentHash
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(users[msg.sender].isActive, "User not registered");
        require(_level != VerificationLevel.None, "Invalid level");
        require(bytes(_documentHash).length > 0, "Document hash required");

        uint256 fee;
        if (_level == VerificationLevel.Basic) {
            fee = VERIFICATION_FEE_BASIC;
        } else if (_level == VerificationLevel.Advanced) {
            fee = VERIFICATION_FEE_ADVANCED;
        } else if (_level == VerificationLevel.Premium) {
            fee = VERIFICATION_FEE_PREMIUM;
        }

        require(msg.value >= fee, "Insufficient verification fee");

        verificationRequests[msg.sender] = VerificationRequest({
            user: msg.sender,
            requestedLevel: _level,
            documentHash: _documentHash,
            submittedAt: block.timestamp,
            isApproved: false,
            isRejected: false,
            rejectionReason: ""
        });

        emit VerificationSubmitted(msg.sender, _level, block.timestamp);
    }

    /**
     * @dev Approve verification (verifier only)
     */
    function approveVerification(address _user) 
        external 
        nonReentrant 
    {
        require(isVerifier[msg.sender], "Not a verifier");
        
        VerificationRequest storage request = verificationRequests[_user];
        require(!request.isApproved && !request.isRejected, "Already processed");

        User storage user = users[_user];
        user.verificationLevel = request.requestedLevel;
        user.verifiedAt = block.timestamp;
        user.trustScore += 25;

        hasVerificationLevel[_user][request.requestedLevel] = true;
        request.isApproved = true;

        emit VerificationApproved(_user, request.requestedLevel, block.timestamp);
    }

    /**
     * @dev Reject verification (verifier only)
     */
    function rejectVerification(address _user, string memory _reason) 
        external 
        nonReentrant 
    {
        require(isVerifier[msg.sender], "Not a verifier");
        
        VerificationRequest storage request = verificationRequests[_user];
        require(!request.isApproved && !request.isRejected, "Already processed");

        request.isRejected = true;
        request.rejectionReason = _reason;

        // Refund verification fee
        uint256 refund;
        if (request.requestedLevel == VerificationLevel.Basic) {
            refund = VERIFICATION_FEE_BASIC;
        } else if (request.requestedLevel == VerificationLevel.Advanced) {
            refund = VERIFICATION_FEE_ADVANCED;
        } else if (request.requestedLevel == VerificationLevel.Premium) {
            refund = VERIFICATION_FEE_PREMIUM;
        }

        (bool success, ) = payable(_user).call{value: refund}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Send verified message
     */
    function sendMessage(
        address _recipient,
        string memory _content,
        bool _requiresVerification,
        VerificationLevel _minLevel,
        bool _isEncrypted
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(users[msg.sender].isActive, "Sender not registered");
        require(users[_recipient].isActive, "Recipient not registered");
        require(_recipient != msg.sender, "Cannot message yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(msg.value >= MESSAGE_FEE_VERIFIED, "Insufficient fee");

        if (_requiresVerification) {
            require(
                uint8(users[msg.sender].verificationLevel) >= uint8(_minLevel),
                "Sender verification insufficient"
            );
            require(
                uint8(users[_recipient].verificationLevel) >= uint8(_minLevel),
                "Recipient verification insufficient"
            );
        }

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        messages[messageId] = Message({
            id: messageId,
            sender: msg.sender,
            recipient: _recipient,
            content: _content,
            timestamp: block.timestamp,
            requiresVerification: _requiresVerification,
            minVerificationLevel: _minLevel,
            isEncrypted: _isEncrypted
        });

        sentMessages[msg.sender].push(messageId);
        receivedMessages[_recipient].push(messageId);
        
        users[msg.sender].messagesSent++;
        users[_recipient].messagesReceived++;

        emit MessageSent(messageId, msg.sender, _recipient, block.timestamp);

        return messageId;
    }

    /**
     * @dev Create trust connection
     */
    function createTrustConnection(
        address _user,
        TrustLevel _level,
        string memory _note
    ) 
        external 
        nonReentrant 
    {
        require(users[msg.sender].isActive, "Sender not registered");
        require(users[_user].isActive, "User not registered");
        require(_user != msg.sender, "Cannot trust yourself");

        trustConnections[msg.sender][_user] = TrustConnection({
            user1: msg.sender,
            user2: _user,
            level: _level,
            createdAt: block.timestamp,
            note: _note
        });

        trustedUsers[msg.sender].push(_user);
        users[_user].trustScore += 5;

        emit TrustConnectionCreated(msg.sender, _user, block.timestamp);
    }

    /**
     * @dev Update user profile
     */
    function updateProfile(string memory _profileHash) 
        external 
    {
        require(users[msg.sender].isActive, "User not registered");
        users[msg.sender].profileHash = _profileHash;
    }

    /**
     * @dev Add verifier (owner only)
     */
    function addVerifier(address _verifier) 
        external 
        onlyOwner 
    {
        require(!isVerifier[_verifier], "Already a verifier");
        
        verifiers.push(_verifier);
        isVerifier[_verifier] = true;
    }

    /**
     * @dev Remove verifier (owner only)
     */
    function removeVerifier(address _verifier) 
        external 
        onlyOwner 
    {
        require(isVerifier[_verifier], "Not a verifier");
        isVerifier[_verifier] = false;
    }

    /**
     * @dev Get user info
     */
    function getUser(address _user) 
        external 
        view 
        returns (
            string memory username,
            VerificationLevel verificationLevel,
            uint256 verifiedAt,
            uint256 messagesSent,
            uint256 messagesReceived,
            uint256 trustScore,
            bool isActive
        )
    {
        User memory user = users[_user];
        return (
            user.username,
            user.verificationLevel,
            user.verifiedAt,
            user.messagesSent,
            user.messagesReceived,
            user.trustScore,
            user.isActive
        );
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
            bool requiresVerification,
            VerificationLevel minVerificationLevel
        )
    {
        Message memory message = messages[_messageId];
        require(
            message.sender == msg.sender || message.recipient == msg.sender,
            "Not authorized to view message"
        );
        
        return (
            message.id,
            message.sender,
            message.recipient,
            message.content,
            message.timestamp,
            message.requiresVerification,
            message.minVerificationLevel
        );
    }

    /**
     * @dev Get trust level between users
     */
    function getTrustLevel(address _user1, address _user2) 
        external 
        view 
        returns (TrustLevel) 
    {
        return trustConnections[_user1][_user2].level;
    }

    /**
     * @dev Get sent messages
     */
    function getSentMessages(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sentMessages[_user];
    }

    /**
     * @dev Get received messages
     */
    function getReceivedMessages(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return receivedMessages[_user];
    }

    /**
     * @dev Get trusted users
     */
    function getTrustedUsers(address _user) 
        external 
        view 
        returns (address[] memory) 
    {
        return trustedUsers[_user];
    }

    /**
     * @dev Check if user is verified
     */
    function isVerified(address _user, VerificationLevel _minLevel) 
        external 
        view 
        returns (bool) 
    {
        return uint8(users[_user].verificationLevel) >= uint8(_minLevel);
    }

    /**
     * @dev Withdraw platform fees (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
