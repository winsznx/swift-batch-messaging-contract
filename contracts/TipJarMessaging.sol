// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title TipJarMessaging
 * @dev Tip-based messaging where users can send messages with tips attached
 * @author Swift v2 Team
 */
contract TipJarMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event TipJarCreated(
        uint256 indexed jarId,
        address indexed creator,
        uint256 timestamp
    );

    event TipMessageSent(
        uint256 indexed messageId,
        uint256 indexed jarId,
        address indexed sender,
        uint256 tipAmount,
        uint256 timestamp
    );

    event TipsWithdrawn(
        uint256 indexed jarId,
        address indexed owner,
        uint256 amount,
        uint256 timestamp
    );

    // Structs
    struct TipJar {
        uint256 id;
        address owner;
        string name;
        string description;
        string category;
        uint256 totalTips;
        uint256 messageCount;
        uint256 minTip;
        bool isActive;
        uint256 createdAt;
    }

    struct TipMessage {
        uint256 id;
        uint256 jarId;
        address sender;
        string content;
        uint256 tipAmount;
        uint256 timestamp;
        bool isAnonymous;
        string senderName;
    }

    // State variables
    Counters.Counter private _jarIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => TipJar) public tipJars;
    mapping(uint256 => TipMessage) public tipMessages;
    mapping(uint256 => uint256[]) public jarMessages;
    mapping(address => uint256[]) public userJars;
    mapping(address => uint256[]) public userSentTips;
    mapping(address => uint256) public pendingWithdrawals;

    // Constants
    uint256 public constant MIN_TIP_AMOUNT = 0.00001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 500;
    uint256 public constant JAR_CREATION_FEE = 0.00001 ether;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 3;

    constructor() {
        _jarIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create tip jar
     */
    function createTipJar(
        string memory _name,
        string memory _description,
        string memory _category,
        uint256 _minTip
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= JAR_CREATION_FEE, "Insufficient fee");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_minTip >= MIN_TIP_AMOUNT, "Min tip too low");

        uint256 jarId = _jarIdCounter.current();
        _jarIdCounter.increment();

        tipJars[jarId] = TipJar({
            id: jarId,
            owner: msg.sender,
            name: _name,
            description: _description,
            category: _category,
            totalTips: 0,
            messageCount: 0,
            minTip: _minTip,
            isActive: true,
            createdAt: block.timestamp
        });

        userJars[msg.sender].push(jarId);

        emit TipJarCreated(jarId, msg.sender, block.timestamp);

        return jarId;
    }

    /**
     * @dev Send tip message
     */
    function sendTipMessage(
        uint256 _jarId,
        string memory _content,
        bool _isAnonymous,
        string memory _senderName
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        TipJar storage jar = tipJars[_jarId];
        require(jar.isActive, "Jar not active");
        require(msg.value >= jar.minTip, "Tip below minimum");
        require(bytes(_content).length > 0, "Empty message");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Message too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        tipMessages[messageId] = TipMessage({
            id: messageId,
            jarId: _jarId,
            sender: msg.sender,
            content: _content,
            tipAmount: msg.value,
            timestamp: block.timestamp,
            isAnonymous: _isAnonymous,
            senderName: _senderName
        });

        jarMessages[_jarId].push(messageId);
        userSentTips[msg.sender].push(messageId);
        
        // Calculate platform fee
        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 ownerAmount = msg.value - platformFee;

        jar.totalTips += ownerAmount;
        jar.messageCount++;
        pendingWithdrawals[jar.owner] += ownerAmount;

        emit TipMessageSent(messageId, _jarId, msg.sender, msg.value, block.timestamp);

        return messageId;
    }

    /**
     * @dev Withdraw tips
     */
    function withdrawTips() 
        external 
        nonReentrant 
    {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No tips to withdraw");

        pendingWithdrawals[msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Withdraw failed");

        emit TipsWithdrawn(0, msg.sender, amount, block.timestamp);
    }

    /**
     * @dev Toggle jar status
     */
    function toggleJarStatus(uint256 _jarId) 
        external 
    {
        TipJar storage jar = tipJars[_jarId];
        require(jar.owner == msg.sender, "Only owner can toggle");
        
        jar.isActive = !jar.isActive;
    }

    /**
     * @dev Update minimum tip
     */
    function updateMinTip(uint256 _jarId, uint256 _minTip) 
        external 
    {
        TipJar storage jar = tipJars[_jarId];
        require(jar.owner == msg.sender, "Only owner can update");
        require(_minTip >= MIN_TIP_AMOUNT, "Min tip too low");
        
        jar.minTip = _minTip;
    }

    /**
     * @dev Get tip jar details
     */
    function getTipJar(uint256 _jarId) 
        external 
        view 
        returns (
            uint256 id,
            address owner,
            string memory name,
            string memory description,
            uint256 totalTips,
            uint256 messageCount,
            uint256 minTip,
            bool isActive
        )
    {
        TipJar memory jar = tipJars[_jarId];
        return (
            jar.id,
            jar.owner,
            jar.name,
            jar.description,
            jar.totalTips,
            jar.messageCount,
            jar.minTip,
            jar.isActive
        );
    }

    /**
     * @dev Get tip message details
     */
    function getTipMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 jarId,
            address sender,
            string memory content,
            uint256 tipAmount,
            uint256 timestamp,
            bool isAnonymous,
            string memory senderName
        )
    {
        TipMessage memory message = tipMessages[_messageId];
        return (
            message.id,
            message.jarId,
            message.isAnonymous ? address(0) : message.sender,
            message.content,
            message.tipAmount,
            message.timestamp,
            message.isAnonymous,
            message.senderName
        );
    }

    /**
     * @dev Get jar's messages
     */
    function getJarMessages(uint256 _jarId) external view returns (uint256[] memory) {
        return jarMessages[_jarId];
    }

    /**
     * @dev Get user's jars
     */
    function getUserJars(address _user) external view returns (uint256[] memory) {
        return userJars[_user];
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
