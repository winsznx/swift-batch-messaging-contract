// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title PollMessaging
 * @dev Interactive polling and survey messaging with onchain results
 * @author Swift v2 Team
 */
contract PollMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event PollCreated(
        uint256 indexed pollId,
        address indexed creator,
        uint256 endTime,
        uint256 timestamp
    );

    event VoteCast(
        uint256 indexed pollId,
        address indexed voter,
        uint256 optionIndex,
        uint256 timestamp
    );

    event PollClosed(
        uint256 indexed pollId,
        uint256 winningOption,
        uint256 timestamp
    );

    event CommentAdded(
        uint256 indexed pollId,
        uint256 indexed commentId,
        address indexed commenter,
        uint256 timestamp
    );

    // Enums
    enum PollStatus { Active, Closed, Cancelled }
    enum PollType { SingleChoice, MultipleChoice, Weighted }

    // Structs
    struct Poll {
        uint256 id;
        address creator;
        string question;
        string[] options;
        uint256[] voteCounts;
        PollType pollType;
        PollStatus status;
        uint256 startTime;
        uint256 endTime;
        uint256 totalVotes;
        bool requiresStake;
        uint256 minStake;
        mapping(address => bool) hasVoted;
        mapping(address => uint256[]) userVotes;
    }

    struct PollComment {
        uint256 id;
        uint256 pollId;
        address commenter;
        string content;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _pollIdCounter;
    Counters.Counter private _commentIdCounter;
    mapping(uint256 => Poll) public polls;
    mapping(uint256 => PollComment) public comments;
    mapping(uint256 => uint256[]) public pollComments;
    mapping(address => uint256[]) public userPolls;
    mapping(address => uint256[]) public userVotedPolls;
    mapping(uint256 => mapping(address => uint256)) public stakedAmounts;

    // Constants
    uint256 public constant MAX_OPTIONS = 10;
    uint256 public constant MAX_QUESTION_LENGTH = 500;
    uint256 public constant MAX_OPTION_LENGTH = 200;
    uint256 public constant MAX_COMMENT_LENGTH = 500;
    uint256 public constant POLL_CREATION_FEE = 0.00001 ether;
    uint256 public constant MIN_POLL_DURATION = 1 hours;
    uint256 public constant MAX_POLL_DURATION = 30 days;

    constructor() {
        _pollIdCounter.increment();
        _commentIdCounter.increment();
    }

    /**
     * @dev Create poll
     */
    function createPoll(
        string memory _question,
        string[] memory _options,
        PollType _pollType,
        uint256 _duration,
        bool _requiresStake,
        uint256 _minStake
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= POLL_CREATION_FEE, "Insufficient fee");
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(bytes(_question).length <= MAX_QUESTION_LENGTH, "Question too long");
        require(_options.length >= 2, "Need at least 2 options");
        require(_options.length <= MAX_OPTIONS, "Too many options");
        require(_duration >= MIN_POLL_DURATION, "Duration too short");
        require(_duration <= MAX_POLL_DURATION, "Duration too long");

        uint256 pollId = _pollIdCounter.current();
        _pollIdCounter.increment();

        Poll storage poll = polls[pollId];
        poll.id = pollId;
        poll.creator = msg.sender;
        poll.question = _question;
        poll.pollType = _pollType;
        poll.status = PollStatus.Active;
        poll.startTime = block.timestamp;
        poll.endTime = block.timestamp + _duration;
        poll.totalVotes = 0;
        poll.requiresStake = _requiresStake;
        poll.minStake = _minStake;

        for (uint256 i = 0; i < _options.length; i++) {
            require(bytes(_options[i]).length <= MAX_OPTION_LENGTH, "Option too long");
            poll.options.push(_options[i]);
            poll.voteCounts.push(0);
        }

        userPolls[msg.sender].push(pollId);

        emit PollCreated(pollId, msg.sender, poll.endTime, block.timestamp);

        return pollId;
    }

    /**
     * @dev Cast vote
     */
    function vote(
        uint256 _pollId,
        uint256[] memory _optionIndices
    ) 
        external 
        payable 
        nonReentrant 
    {
        Poll storage poll = polls[_pollId];
        require(poll.status == PollStatus.Active, "Poll not active");
        require(block.timestamp < poll.endTime, "Poll ended");
        require(!poll.hasVoted[msg.sender], "Already voted");
        require(_optionIndices.length > 0, "No options selected");

        if (poll.requiresStake) {
            require(msg.value >= poll.minStake, "Insufficient stake");
            stakedAmounts[_pollId][msg.sender] = msg.value;
        }

        if (poll.pollType == PollType.SingleChoice) {
            require(_optionIndices.length == 1, "Single choice only");
            require(_optionIndices[0] < poll.options.length, "Invalid option");
            
            poll.voteCounts[_optionIndices[0]]++;
            poll.userVotes[msg.sender].push(_optionIndices[0]);
        } else if (poll.pollType == PollType.MultipleChoice) {
            for (uint256 i = 0; i < _optionIndices.length; i++) {
                require(_optionIndices[i] < poll.options.length, "Invalid option");
                poll.voteCounts[_optionIndices[i]]++;
                poll.userVotes[msg.sender].push(_optionIndices[i]);
            }
        }

        poll.hasVoted[msg.sender] = true;
        poll.totalVotes++;
        userVotedPolls[msg.sender].push(_pollId);

        emit VoteCast(_pollId, msg.sender, _optionIndices[0], block.timestamp);
    }

    /**
     * @dev Close poll
     */
    function closePoll(uint256 _pollId) 
        external 
        nonReentrant 
    {
        Poll storage poll = polls[_pollId];
        require(poll.creator == msg.sender || block.timestamp >= poll.endTime, "Cannot close");
        require(poll.status == PollStatus.Active, "Poll not active");

        poll.status = PollStatus.Closed;

        // Find winning option
        uint256 winningOption = 0;
        uint256 maxVotes = 0;
        for (uint256 i = 0; i < poll.voteCounts.length; i++) {
            if (poll.voteCounts[i] > maxVotes) {
                maxVotes = poll.voteCounts[i];
                winningOption = i;
            }
        }

        emit PollClosed(_pollId, winningOption, block.timestamp);
    }

    /**
     * @dev Add comment to poll
     */
    function addComment(
        uint256 _pollId,
        string memory _content
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Poll storage poll = polls[_pollId];
        require(poll.id != 0, "Poll doesn't exist");
        require(bytes(_content).length > 0, "Empty comment");
        require(bytes(_content).length <= MAX_COMMENT_LENGTH, "Comment too long");

        uint256 commentId = _commentIdCounter.current();
        _commentIdCounter.increment();

        comments[commentId] = PollComment({
            id: commentId,
            pollId: _pollId,
            commenter: msg.sender,
            content: _content,
            timestamp: block.timestamp
        });

        pollComments[_pollId].push(commentId);

        emit CommentAdded(_pollId, commentId, msg.sender, block.timestamp);

        return commentId;
    }

    /**
     * @dev Claim staked amount after poll closes
     */
    function claimStake(uint256 _pollId) 
        external 
        nonReentrant 
    {
        Poll storage poll = polls[_pollId];
        require(poll.status == PollStatus.Closed, "Poll not closed");
        
        uint256 stake = stakedAmounts[_pollId][msg.sender];
        require(stake > 0, "No stake to claim");

        stakedAmounts[_pollId][msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: stake}("");
        require(success, "Stake refund failed");
    }

    /**
     * @dev Get poll details
     */
    function getPoll(uint256 _pollId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            string memory question,
            string[] memory options,
            uint256[] memory voteCounts,
            PollType pollType,
            PollStatus status,
            uint256 endTime,
            uint256 totalVotes
        )
    {
        Poll storage poll = polls[_pollId];
        return (
            poll.id,
            poll.creator,
            poll.question,
            poll.options,
            poll.voteCounts,
            poll.pollType,
            poll.status,
            poll.endTime,
            poll.totalVotes
        );
    }

    /**
     * @dev Get poll comments
     */
    function getPollComments(uint256 _pollId) external view returns (uint256[] memory) {
        return pollComments[_pollId];
    }

    /**
     * @dev Get user's created polls
     */
    function getUserPolls(address _user) external view returns (uint256[] memory) {
        return userPolls[_user];
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
