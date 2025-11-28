// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title SubscriptionMessaging
 * @dev A contract with subscription-based messaging channels
 * @author Swift v2 Team
 */
contract SubscriptionMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ChannelCreated(
        uint256 indexed channelId,
        address indexed creator,
        string name,
        uint256 subscriptionFee,
        uint256 timestamp
    );

    event UserSubscribed(
        uint256 indexed channelId,
        address indexed subscriber,
        uint256 expiresAt,
        uint256 timestamp
    );

    event ChannelMessageSent(
        uint256 indexed channelId,
        uint256 indexed messageId,
        address indexed sender,
        uint256 timestamp
    );

    // Structs
    struct Channel {
        uint256 id;
        address creator;
        string name;
        string description;
        uint256 subscriptionFee;
        uint256 subscriptionDuration; // in seconds
        uint256 createdAt;
        bool isActive;
    }

    struct Subscription {
        uint256 channelId;
        address subscriber;
        uint256 subscribedAt;
        uint256 expiresAt;
        bool isActive;
    }

    struct ChannelMessage {
        uint256 id;
        uint256 channelId;
        address sender;
        string content;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _channelIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => Channel) public channels;
    mapping(uint256 => mapping(address => Subscription)) public subscriptions;
    mapping(uint256 => ChannelMessage) public channelMessages;
    mapping(uint256 => uint256[]) public channelMessageIds;
    mapping(address => uint256[]) public userChannels;

    // Constants
    uint256 public constant CHANNEL_CREATION_FEE = 0.00001 ether;
    uint256 public constant MESSAGE_FEE = 0.000001 ether;
    uint256 public constant MIN_SUBSCRIPTION_DURATION = 86400; // 1 day

    constructor() {
        _channelIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create a subscription channel
     * @param _name Channel name
     * @param _description Channel description
     * @param _subscriptionFee Fee to subscribe
     * @param _subscriptionDuration Duration in seconds
     */
    function createChannel(
        string memory _name,
        string memory _description,
        uint256 _subscriptionFee,
        uint256 _subscriptionDuration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= CHANNEL_CREATION_FEE, "Insufficient fee");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_subscriptionDuration >= MIN_SUBSCRIPTION_DURATION, "Duration too short");
        
        uint256 channelId = _channelIdCounter.current();
        _channelIdCounter.increment();

        Channel storage channel = channels[channelId];
        channel.id = channelId;
        channel.creator = msg.sender;
        channel.name = _name;
        channel.description = _description;
        channel.subscriptionFee = _subscriptionFee;
        channel.subscriptionDuration = _subscriptionDuration;
        channel.createdAt = block.timestamp;
        channel.isActive = true;

        userChannels[msg.sender].push(channelId);

        emit ChannelCreated(
            channelId,
            msg.sender,
            _name,
            _subscriptionFee,
            block.timestamp
        );
    }

    /**
     * @dev Subscribe to a channel
     * @param _channelId ID of the channel
     */
    function subscribe(uint256 _channelId) 
        external 
        payable 
        nonReentrant 
    {
        Channel storage channel = channels[_channelId];
        require(channel.isActive, "Channel not active");
        require(msg.value >= channel.subscriptionFee, "Insufficient subscription fee");
        
        Subscription storage sub = subscriptions[_channelId][msg.sender];
        
        uint256 startTime = block.timestamp;
        if (sub.expiresAt > block.timestamp) {
            startTime = sub.expiresAt; // Extend existing subscription
        }
        
        uint256 expiresAt = startTime + channel.subscriptionDuration;
        
        sub.channelId = _channelId;
        sub.subscriber = msg.sender;
        sub.subscribedAt = block.timestamp;
        sub.expiresAt = expiresAt;
        sub.isActive = true;

        // Transfer fee to channel creator
        (bool success, ) = payable(channel.creator).call{value: msg.value}("");
        require(success, "Fee transfer failed");

        emit UserSubscribed(_channelId, msg.sender, expiresAt, block.timestamp);
    }

    /**
     * @dev Post message to channel
     * @param _channelId ID of the channel
     * @param _content Message content
     */
    function postToChannel(uint256 _channelId, string memory _content) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MESSAGE_FEE, "Insufficient fee");
        Channel storage channel = channels[_channelId];
        require(channel.isActive, "Channel not active");
        require(channel.creator == msg.sender, "Only creator can post");
        require(bytes(_content).length > 0, "Empty content");
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        ChannelMessage storage message = channelMessages[messageId];
        message.id = messageId;
        message.channelId = _channelId;
        message.sender = msg.sender;
        message.content = _content;
        message.timestamp = block.timestamp;

        channelMessageIds[_channelId].push(messageId);

        emit ChannelMessageSent(_channelId, messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Check if user has active subscription
     */
    function hasActiveSubscription(uint256 _channelId, address _user) 
        external 
        view 
        returns (bool)
    {
        Subscription storage sub = subscriptions[_channelId][_user];
        return sub.isActive && sub.expiresAt > block.timestamp;
    }

    /**
     * @dev Get channel details
     */
    function getChannel(uint256 _channelId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            string memory name,
            string memory description,
            uint256 subscriptionFee,
            uint256 subscriptionDuration,
            uint256 createdAt,
            bool isActive
        )
    {
        Channel storage channel = channels[_channelId];
        return (
            channel.id,
            channel.creator,
            channel.name,
            channel.description,
            channel.subscriptionFee,
            channel.subscriptionDuration,
            channel.createdAt,
            channel.isActive
        );
    }

    /**
     * @dev Get channel messages
     */
    function getChannelMessages(uint256 _channelId) 
        external 
        view 
        returns (uint256[] memory)
    {
        return channelMessageIds[_channelId];
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
