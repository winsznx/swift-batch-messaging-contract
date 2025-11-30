// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title GroupMessaging
 * @dev Decentralized group chat with admin controls and member management
 * @author Swift v2 Team
 */
contract GroupMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event GroupCreated(
        uint256 indexed groupId,
        address indexed creator,
        string name,
        uint256 timestamp
    );

    event MemberAdded(
        uint256 indexed groupId,
        address indexed member,
        address indexed addedBy,
        uint256 timestamp
    );

    event MemberRemoved(
        uint256 indexed groupId,
        address indexed member,
        address indexed removedBy,
        uint256 timestamp
    );

    event GroupMessageSent(
        uint256 indexed messageId,
        uint256 indexed groupId,
        address indexed sender,
        uint256 timestamp
    );

    event AdminAdded(
        uint256 indexed groupId,
        address indexed admin,
        address indexed addedBy,
        uint256 timestamp
    );

    event GroupSettingsUpdated(
        uint256 indexed groupId,
        uint256 timestamp
    );

    // Structs
    struct Group {
        uint256 id;
        string name;
        string description;
        address creator;
        uint256 createdAt;
        bool isPublic;
        bool membersCanInvite;
        bool anyoneCanMessage;
        uint256 maxMembers;
        uint256 memberCount;
        mapping(address => bool) isMember;
        mapping(address => bool) isAdmin;
        address[] members;
        address[] admins;
    }

    struct GroupMessage {
        uint256 id;
        uint256 groupId;
        address sender;
        string content;
        uint256 timestamp;
        bool isPinned;
        uint256 replyToMessageId;
    }

    // State variables
    Counters.Counter private _groupIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => Group) public groups;
    mapping(uint256 => GroupMessage) public groupMessages;
    mapping(uint256 => uint256[]) public groupMessageList;
    mapping(address => uint256[]) public userGroups;
    mapping(uint256 => uint256[]) public pinnedMessages;

    // Constants
    uint256 public constant MAX_GROUP_NAME_LENGTH = 100;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant DEFAULT_MAX_MEMBERS = 1000;
    uint256 public constant GROUP_CREATION_FEE = 0.0001 ether;
    uint256 public constant MESSAGE_FEE = 0.000001 ether;

    constructor() {
        _groupIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create new group
     */
    function createGroup(
        string memory _name,
        string memory _description,
        bool _isPublic,
        bool _membersCanInvite,
        uint256 _maxMembers
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= GROUP_CREATION_FEE, "Insufficient fee");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_name).length <= MAX_GROUP_NAME_LENGTH, "Name too long");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_maxMembers > 0 && _maxMembers <= DEFAULT_MAX_MEMBERS, "Invalid max members");

        uint256 groupId = _groupIdCounter.current();
        _groupIdCounter.increment();

        Group storage group = groups[groupId];
        group.id = groupId;
        group.name = _name;
        group.description = _description;
        group.creator = msg.sender;
        group.createdAt = block.timestamp;
        group.isPublic = _isPublic;
        group.membersCanInvite = _membersCanInvite;
        group.anyoneCanMessage = true;
        group.maxMembers = _maxMembers;
        group.memberCount = 1;

        // Add creator as first member and admin
        group.isMember[msg.sender] = true;
        group.isAdmin[msg.sender] = true;
        group.members.push(msg.sender);
        group.admins.push(msg.sender);

        userGroups[msg.sender].push(groupId);

        emit GroupCreated(groupId, msg.sender, _name, block.timestamp);
        emit AdminAdded(groupId, msg.sender, msg.sender, block.timestamp);

        return groupId;
    }

    /**
     * @dev Add member to group
     */
    function addMember(uint256 _groupId, address _member) 
        external 
        nonReentrant 
    {
        Group storage group = groups[_groupId];
        require(group.id != 0, "Group doesn't exist");
        require(!group.isMember[_member], "Already a member");
        require(group.memberCount < group.maxMembers, "Group is full");
        require(
            group.isAdmin[msg.sender] || 
            (group.membersCanInvite && group.isMember[msg.sender]) ||
            group.isPublic,
            "Not authorized to add members"
        );

        group.isMember[_member] = true;
        group.members.push(_member);
        group.memberCount++;
        userGroups[_member].push(_groupId);

        emit MemberAdded(_groupId, _member, msg.sender, block.timestamp);
    }

    /**
     * @dev Remove member from group
     */
    function removeMember(uint256 _groupId, address _member) 
        external 
        nonReentrant 
    {
        Group storage group = groups[_groupId];
        require(group.id != 0, "Group doesn't exist");
        require(group.isMember[_member], "Not a member");
        require(group.isAdmin[msg.sender], "Only admins can remove");
        require(_member != group.creator, "Cannot remove creator");

        group.isMember[_member] = false;
        group.memberCount--;

        // Remove admin status if applicable
        if (group.isAdmin[_member]) {
            group.isAdmin[_member] = false;
        }

        emit MemberRemoved(_groupId, _member, msg.sender, block.timestamp);
    }

    /**
     * @dev Add admin to group
     */
    function addAdmin(uint256 _groupId, address _newAdmin) 
        external 
        nonReentrant 
    {
        Group storage group = groups[_groupId];
        require(group.id != 0, "Group doesn't exist");
        require(group.creator == msg.sender, "Only creator can add admins");
        require(group.isMember[_newAdmin], "Must be a member");
        require(!group.isAdmin[_newAdmin], "Already an admin");

        group.isAdmin[_newAdmin] = true;
        group.admins.push(_newAdmin);

        emit AdminAdded(_groupId, _newAdmin, msg.sender, block.timestamp);
    }

    /**
     * @dev Send message to group
     */
    function sendGroupMessage(
        uint256 _groupId,
        string memory _content,
        uint256 _replyToMessageId
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        Group storage group = groups[_groupId];
        require(group.id != 0, "Group doesn't exist");
        require(group.isMember[msg.sender], "Not a group member");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(msg.value >= MESSAGE_FEE, "Insufficient fee");

        if (_replyToMessageId != 0) {
            require(
                groupMessages[_replyToMessageId].groupId == _groupId,
                "Reply message not in this group"
            );
        }

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        groupMessages[messageId] = GroupMessage({
            id: messageId,
            groupId: _groupId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isPinned: false,
            replyToMessageId: _replyToMessageId
        });

        groupMessageList[_groupId].push(messageId);

        emit GroupMessageSent(messageId, _groupId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Pin message (admin only)
     */
    function pinMessage(uint256 _messageId) 
        external 
        nonReentrant 
    {
        GroupMessage storage message = groupMessages[_messageId];
        require(message.id != 0, "Message doesn't exist");
        
        Group storage group = groups[message.groupId];
        require(group.isAdmin[msg.sender], "Only admins can pin");
        require(!message.isPinned, "Already pinned");

        message.isPinned = true;
        pinnedMessages[message.groupId].push(_messageId);
    }

    /**
     * @dev Update group settings (admin only)
     */
    function updateGroupSettings(
        uint256 _groupId,
        bool _membersCanInvite,
        bool _anyoneCanMessage
    ) 
        external 
        nonReentrant 
    {
        Group storage group = groups[_groupId];
        require(group.id != 0, "Group doesn't exist");
        require(group.isAdmin[msg.sender], "Only admins can update");

        group.membersCanInvite = _membersCanInvite;
        group.anyoneCanMessage = _anyoneCanMessage;

        emit GroupSettingsUpdated(_groupId, block.timestamp);
    }

    /**
     * @dev Leave group
     */
    function leaveGroup(uint256 _groupId) 
        external 
        nonReentrant 
    {
        Group storage group = groups[_groupId];
        require(group.id != 0, "Group doesn't exist");
        require(group.isMember[msg.sender], "Not a member");
        require(group.creator != msg.sender, "Creator cannot leave");

        group.isMember[msg.sender] = false;
        group.memberCount--;

        if (group.isAdmin[msg.sender]) {
            group.isAdmin[msg.sender] = false;
        }

        emit MemberRemoved(_groupId, msg.sender, msg.sender, block.timestamp);
    }

    /**
     * @dev Get group info
     */
    function getGroupInfo(uint256 _groupId) 
        external 
        view 
        returns (
            uint256 id,
            string memory name,
            string memory description,
            address creator,
            uint256 createdAt,
            bool isPublic,
            uint256 memberCount,
            uint256 maxMembers
        )
    {
        Group storage group = groups[_groupId];
        return (
            group.id,
            group.name,
            group.description,
            group.creator,
            group.createdAt,
            group.isPublic,
            group.memberCount,
            group.maxMembers
        );
    }

    /**
     * @dev Get group members
     */
    function getGroupMembers(uint256 _groupId) 
        external 
        view 
        returns (address[] memory) 
    {
        return groups[_groupId].members;
    }

    /**
     * @dev Get group admins
     */
    function getGroupAdmins(uint256 _groupId) 
        external 
        view 
        returns (address[] memory) 
    {
        return groups[_groupId].admins;
    }

    /**
     * @dev Get group messages
     */
    function getGroupMessages(uint256 _groupId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return groupMessageList[_groupId];
    }

    /**
     * @dev Get pinned messages
     */
    function getPinnedMessages(uint256 _groupId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return pinnedMessages[_groupId];
    }

    /**
     * @dev Check if user is member
     */
    function isMember(uint256 _groupId, address _user) 
        external 
        view 
        returns (bool) 
    {
        return groups[_groupId].isMember[_user];
    }

    /**
     * @dev Check if user is admin
     */
    function isAdmin(uint256 _groupId, address _user) 
        external 
        view 
        returns (bool) 
    {
        return groups[_groupId].isAdmin[_user];
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
