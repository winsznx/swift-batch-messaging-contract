// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title ThreadedMessaging
 * @dev A contract supporting message threads with reply functionality
 * @author Swift v2 Team
 */
contract ThreadedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ThreadCreated(
        uint256 indexed threadId,
        address indexed creator,
        string subject,
        uint256 timestamp
    );

    event MessagePosted(
        uint256 indexed threadId,
        uint256 indexed messageId,
        address indexed sender,
        uint256 timestamp
    );

    // Structs
    struct Thread {
        uint256 id;
        address creator;
        string subject;
        uint256[] messageIds;
        address[] participants;
        mapping(address => bool) isParticipant;
        uint256 createdAt;
        bool isLocked;
    }

    struct ThreadMessage {
        uint256 id;
        uint256 threadId;
        address sender;
        string content;
        uint256 timestamp;
        uint256 replyToId; // 0 if not a reply
    }

    // State variables
    Counters.Counter private _threadIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => Thread) public threads;
    mapping(uint256 => ThreadMessage) public threadMessages;
    mapping(address => uint256[]) public userThreads;

    // Constants
    uint256 public constant THREAD_CREATION_FEE = 0.000003 ether;
    uint256 public constant MESSAGE_FEE = 0.000001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    // Modifiers
    modifier threadExists(uint256 _threadId) {
        require(_threadId > 0 && _threadId <= _threadIdCounter.current(), "Thread does not exist");
        _;
    }

    modifier threadActive(uint256 _threadId) {
        require(!threads[_threadId].isLocked, "Thread is locked");
        _;
    }

    modifier isThreadParticipant(uint256 _threadId) {
        require(
            threads[_threadId].creator == msg.sender || threads[_threadId].isParticipant[msg.sender],
            "Not a participant"
        );
        _;
    }

    constructor() {
        _threadIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create a new message thread
     * @param _subject Subject of the thread
     * @param _initialParticipants Initial participants
     */
    function createThread(
        string memory _subject,
        address[] memory _initialParticipants
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= THREAD_CREATION_FEE, "Insufficient fee");
        require(bytes(_subject).length > 0, "Subject cannot be empty");
        
        uint256 threadId = _threadIdCounter.current();
        _threadIdCounter.increment();

        Thread storage thread = threads[threadId];
        thread.id = threadId;
        thread.creator = msg.sender;
        thread.subject = _subject;
        thread.createdAt = block.timestamp;
        thread.isLocked = false;

        thread.participants.push(msg.sender);
        thread.isParticipant[msg.sender] = true;

        for (uint256 i = 0; i < _initialParticipants.length; i++) {
            address participant = _initialParticipants[i];
            if (participant != address(0) && !thread.isParticipant[participant]) {
                thread.participants.push(participant);
                thread.isParticipant[participant] = true;
            }
        }

        userThreads[msg.sender].push(threadId);

        emit ThreadCreated(threadId, msg.sender, _subject, block.timestamp);
    }

    /**
     * @dev Post a message to a thread
     * @param _threadId ID of the thread
     * @param _content Message content
     * @param _replyToId ID of message being replied to (0 if not a reply)
     */
    function postMessage(
        uint256 _threadId,
        string memory _content,
        uint256 _replyToId
    ) 
        external 
        payable 
        nonReentrant 
        threadExists(_threadId)
        threadActive(_threadId)
        isThreadParticipant(_threadId)
    {
        require(msg.value >= MESSAGE_FEE, "Insufficient fee");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        if (_replyToId > 0) {
            require(threadMessages[_replyToId].threadId == _threadId, "Reply not in same thread");
        }
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        ThreadMessage storage message = threadMessages[messageId];
        message.id = messageId;
        message.threadId = _threadId;
        message.sender = msg.sender;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.replyToId = _replyToId;

        threads[_threadId].messageIds.push(messageId);

        emit MessagePosted(_threadId, messageId, msg.sender, block.timestamp);
    }

    /**
     * @dev Add participant to thread
     * @param _threadId ID of the thread
     * @param _participant Address to add
     */
    function addParticipant(uint256 _threadId, address _participant) 
        external 
        threadExists(_threadId)
    {
        Thread storage thread = threads[_threadId];
        require(thread.creator == msg.sender, "Only creator can add participants");
        require(_participant != address(0), "Invalid address");
        require(!thread.isParticipant[_participant], "Already a participant");

        thread.participants.push(_participant);
        thread.isParticipant[_participant] = true;
        userThreads[_participant].push(_threadId);
    }

    /**
     * @dev Lock a thread to prevent new messages
     * @param _threadId ID of the thread
     */
    function lockThread(uint256 _threadId) 
        external 
        threadExists(_threadId)
    {
        require(threads[_threadId].creator == msg.sender, "Only creator can lock");
        threads[_threadId].isLocked = true;
    }

    /**
     * @dev Get thread details
     */
    function getThread(uint256 _threadId) 
        external 
        view 
        threadExists(_threadId)
        returns (
            uint256 id,
            address creator,
            string memory subject,
            uint256[] memory messageIds,
            address[] memory participants,
            uint256 createdAt,
            bool isLocked
        )
    {
        Thread storage thread = threads[_threadId];
        return (
            thread.id,
            thread.creator,
            thread.subject,
            thread.messageIds,
            thread.participants,
            thread.createdAt,
            thread.isLocked
        );
    }

    /**
     * @dev Get thread message details
     */
    function getThreadMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 threadId,
            address sender,
            string memory content,
            uint256 timestamp,
            uint256 replyToId
        )
    {
        ThreadMessage storage message = threadMessages[_messageId];
        return (
            message.id,
            message.threadId,
            message.sender,
            message.content,
            message.timestamp,
            message.replyToId
        );
    }

    /**
     * @dev Get user's threads
     */
    function getUserThreads(address _user) external view returns (uint256[] memory) {
        return userThreads[_user];
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
