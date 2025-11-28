// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title VotingMessaging
 * @dev A contract for poll/voting messages where recipients can vote on options
 * @author Swift v2 Team
 */
contract VotingMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event PollCreated(
        uint256 indexed pollId,
        address indexed creator,
        string question,
        uint256 votingDeadline,
        uint256 timestamp
    );

    event VoteCasted(
        uint256 indexed pollId,
        address indexed voter,
        uint256 optionIndex,
        uint256 timestamp
    );

    event PollClosed(
        uint256 indexed pollId,
        uint256 timestamp
    );

    // Structs
    struct Poll {
        uint256 id;
        address creator;
        string question;
        string[] options;
        mapping(uint256 => uint256) votes; // optionIndex => voteCount
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voterChoice;
        address[] voters;
        uint256 votingDeadline;
        uint256 createdAt;
        bool isClosed;
    }

    // State variables
    Counters.Counter private _pollIdCounter;
    mapping(uint256 => Poll) public polls;
    mapping(address => uint256[]) public userPolls;

    // Constants
    uint256 public constant POLL_CREATION_FEE = 0.000003 ether;
    uint256 public constant MAX_OPTIONS = 20;
    uint256 public constant MIN_VOTING_DURATION = 300; // 5 minutes

    // Modifiers
    modifier pollExists(uint256 _pollId) {
        require(_pollId > 0 && _pollId <= _pollIdCounter.current(), "Poll does not exist");
        _;
    }

    modifier pollActive(uint256 _pollId) {
        require(!polls[_pollId].isClosed, "Poll is closed");
        require(block.timestamp < polls[_pollId].votingDeadline, "Voting period ended");
        _;
    }

    modifier onlyPollCreator(uint256 _pollId) {
        require(polls[_pollId].creator == msg.sender, "Only creator can perform this action");
        _;
    }

    constructor() {
        _pollIdCounter.increment();
    }

    /**
     * @dev Create a new poll
     * @param _question The poll question
     * @param _options Array of voting options
     * @param _votingDuration Duration in seconds
     */
    function createPoll(
        string memory _question,
        string[] memory _options,
        uint256 _votingDuration
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= POLL_CREATION_FEE, "Insufficient fee");
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(_options.length >= 2, "Need at least 2 options");
        require(_options.length <= MAX_OPTIONS, "Too many options");
        require(_votingDuration >= MIN_VOTING_DURATION, "Voting duration too short");
        
        uint256 pollId = _pollIdCounter.current();
        _pollIdCounter.increment();

        Poll storage poll = polls[pollId];
        poll.id = pollId;
        poll.creator = msg.sender;
        poll.question = _question;
        poll.votingDeadline = block.timestamp + _votingDuration;
        poll.createdAt = block.timestamp;
        poll.isClosed = false;

        // Add options
        for (uint256 i = 0; i < _options.length; i++) {
            require(bytes(_options[i]).length > 0, "Empty option not allowed");
            poll.options.push(_options[i]);
        }

        userPolls[msg.sender].push(pollId);

        emit PollCreated(
            pollId,
            msg.sender,
            _question,
            poll.votingDeadline,
            block.timestamp
        );
    }

    /**
     * @dev Cast a vote on a poll
     * @param _pollId ID of the poll
     * @param _optionIndex Index of the chosen option
     */
    function vote(uint256 _pollId, uint256 _optionIndex) 
        external 
        nonReentrant 
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        require(!poll.hasVoted[msg.sender], "Already voted");
        require(_optionIndex < poll.options.length, "Invalid option");

        poll.hasVoted[msg.sender] = true;
        poll.voterChoice[msg.sender] = _optionIndex;
        poll.votes[_optionIndex]++;
        poll.voters.push(msg.sender);

        emit VoteCasted(_pollId, msg.sender, _optionIndex, block.timestamp);
    }

    /**
     * @dev Close a poll manually
     * @param _pollId ID of the poll
     */
    function closePoll(uint256 _pollId) 
        external 
        pollExists(_pollId)
        onlyPollCreator(_pollId)
    {
        Poll storage poll = polls[_pollId];
        require(!poll.isClosed, "Poll already closed");

        poll.isClosed = true;

        emit PollClosed(_pollId, block.timestamp);
    }

    /**
     * @dev Get poll details
     * @param _pollId ID of the poll
     */
    function getPoll(uint256 _pollId) 
        external 
        view 
        pollExists(_pollId)
        returns (
            uint256 id,
            address creator,
            string memory question,
            string[] memory options,
            uint256 votingDeadline,
            uint256 createdAt,
            bool isClosed
        )
    {
        Poll storage poll = polls[_pollId];
        return (
            poll.id,
            poll.creator,
            poll.question,
            poll.options,
            poll.votingDeadline,
            poll.createdAt,
            poll.isClosed
        );
    }

    /**
     * @dev Get vote count for an option
     * @param _pollId ID of the poll
     * @param _optionIndex Index of the option
     */
    function getVoteCount(uint256 _pollId, uint256 _optionIndex) 
        external 
        view 
        pollExists(_pollId)
        returns (uint256)
    {
        require(_optionIndex < polls[_pollId].options.length, "Invalid option");
        return polls[_pollId].votes[_optionIndex];
    }

    /**
     * @dev Check if user has voted
     * @param _pollId ID of the poll
     * @param _user Address of the user
     */
    function hasUserVoted(uint256 _pollId, address _user) 
        external 
        view 
        pollExists(_pollId)
        returns (bool)
    {
        return polls[_pollId].hasVoted[_user];
    }

    /**
     * @dev Get user's choice
     * @param _pollId ID of the poll
     * @param _user Address of the user
     */
    function getUserChoice(uint256 _pollId, address _user) 
        external 
        view 
        pollExists(_pollId)
        returns (uint256)
    {
        require(polls[_pollId].hasVoted[_user], "User has not voted");
        return polls[_pollId].voterChoice[_user];
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
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
