// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title BroadcastMessaging
 * @dev A contract for public broadcast channels with follower subscriptions
 * @author Swift v2 Team
 */
contract BroadcastMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ChannelCreated(
        uint256 indexed channelId,
        address indexed broadcaster,
        string name,
        uint256 timestamp
    );

    event UserFollowed(
        uint256 indexed channelId,
        address indexed follower,
        uint256 timestamp
    );

    event UserUnfollowed(
        uint256 indexed channelId,
        address indexed follower,
        uint256 timestamp
    );

    event BroadcastSent(
        uint256 indexed channelId,
        uint256 indexed broadcastId,
        address indexed broadcaster,
        uint256 timestamp
    );

    // Structs
    struct BroadcastChannel {
        uint256 id;
        address broadcaster;
        string name;
        string description;
        address[] followers;
        mapping(address => bool) isFollower;
        uint256 createdAt;
        bool isActive;
    }

    struct Broadcast {
        uint256 id;
        uint256 channelId;
        address broadcaster;
        string content;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _channelIdCounter;
    Counters.Counter private _broadcastIdCounter;
    mapping(uint256 => BroadcastChannel) public broadcastChannels;
    mapping(uint256 => Broadcast) public broadcasts;
    mapping(uint256 => uint256[]) public channelBroadcasts;
    mapping(address => uint256[]) public userChannels;
    mapping(address => uint256[]) public userFollowing;

    // Constants
    uint256 public constant CHANNEL_CREATION_FEE = 0.000005 ether;
    uint256 public constant BROADCAST_FEE = 0.000002 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _channelIdCounter.increment();
        _broadcastIdCounter.increment();
    }

    /**
     * @dev Create a broadcast channel
     * @param _name Channel name
     * @param _description Channel description
     */
    function createChannel(
        string memory _name,
        string memory _description
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= CHANNEL_CREATION_FEE, "Insufficient fee");
        require(bytes(_name).length > 0, "Name cannot be empty");
        
        uint256 channelId = _channelIdCounter.current();
        _channelIdCounter.increment();

        BroadcastChannel storage channel = broadcastChannels[channelId];
        channel.id = channelId;
        channel.broadcaster = msg.sender;
        channel.name = _name;
        channel.description = _description;
        channel.createdAt = block.timestamp;
        channel.isActive = true;

        userChannels[msg.sender].push(channelId);

        emit ChannelCreated(channelId, msg.sender, _name, block.timestamp);
    }

    /**
     * @dev Follow a broadcast channel
     * @param _channelId ID of the channel
     */
    function followChannel(uint256 _channelId) 
        external 
        nonReentrant 
    {
        BroadcastChannel storage channel = broadcastChannels[_channelId];
        require(channel.isActive, "Channel not active");
        require(!channel.isFollower[msg.sender], "Already following");
        
        channel.followers.push(msg.sender);
        channel.isFollower[msg.sender] = true;
        userFollowing[msg.sender].push(_channelId);

        emit UserFollowed(_channelId, msg.sender, block.timestamp);
    }

    /**
     * @dev Unfollow a broadcast channel
     * @param _channelId ID of the channel
     */
    function unfollowChannel(uint256 _channelId) 
        external 
        nonReentrant 
    {
        BroadcastChannel storage channel = broadcastChannels[_channelId];
        require(channel.isFollower[msg.sender], "Not following");
        
        channel.isFollower[msg.sender] = false;

        emit UserUnfollowed(_channelId, msg.sender, block.timestamp);
    }

    /**
     * @dev Send a broadcast to channel followers
     * @param _channelId ID of the channel
     * @param _content Broadcast content
     */
    function sendBroadcast(uint256 _channelId, string memory _content) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= BROADCAST_FEE, "Insufficient fee");
        BroadcastChannel storage channel = broadcastChannels[_channelId];
        require(channel.isActive, "Channel not active");
        require(channel.broadcaster == msg.sender, "Only broadcaster can send");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 broadcastId = _broadcastIdCounter.current();
        _broadcastIdCounter.increment();

        Broadcast storage broadcast = broadcasts[broadcastId];
        broadcast.id = broadcastId;
        broadcast.channelId = _channelId;
        broadcast.broadcaster = msg.sender;
        broadcast.content = _content;
        broadcast.timestamp = block.timestamp;

        channelBroadcasts[_channelId].push(broadcastId);

        emit BroadcastSent(_channelId, broadcastId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get channel details
     */
    function getChannel(uint256 _channelId) 
        external 
        view 
        returns (
            uint256 id,
            address broadcaster,
            string memory name,
            string memory description,
            uint256 followerCount,
            uint256 createdAt,
            bool isActive
        )
    {
        BroadcastChannel storage channel = broadcastChannels[_channelId];
        return (
            channel.id,
            channel.broadcaster,
            channel.name,
            channel.description,
            channel.followers.length,
            channel.createdAt,
            channel.isActive
        );
    }

    /**
     * @dev Get broadcast details
     */
    function getBroadcast(uint256 _broadcastId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 channelId,
            address broadcaster,
            string memory content,
            uint256 timestamp
        )
    {
        Broadcast storage broadcast = broadcasts[_broadcastId];
        return (
            broadcast.id,
            broadcast.channelId,
            broadcast.broadcaster,
            broadcast.content,
            broadcast.timestamp
        );
    }

    /**
     * @dev Check if user is following channel
     */
    function isFollowing(uint256 _channelId, address _user) 
        external 
        view 
        returns (bool)
    {
        return broadcastChannels[_channelId].isFollower[_user];
    }

    /**
     * @dev Get channel broadcasts
     */
    function getChannelBroadcasts(uint256 _channelId) 
        external 
        view 
        returns (uint256[] memory)
    {
        return channelBroadcasts[_channelId];
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
