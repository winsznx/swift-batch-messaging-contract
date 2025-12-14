// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title AMAMessaging
 * @dev Ask-Me-Anything messaging with host Q&A sessions
 * @author Swift v2 Team
 */
contract AMAMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    event AMASessionCreated(uint256 indexed sessionId, address indexed host, uint256 timestamp);
    event QuestionAsked(uint256 indexed sessionId, uint256 indexed questionId, address indexed asker, uint256 timestamp);
    event QuestionAnswered(uint256 indexed sessionId, uint256 indexed questionId, uint256 timestamp);
    event QuestionUpvoted(uint256 indexed questionId, address indexed voter, uint256 timestamp);

    enum SessionStatus { Scheduled, Live, Ended }
    enum QuestionStatus { Pending, Answered, Skipped }

    struct AMASession {
        uint256 id;
        address host;
        string title;
        string description;
        string topic;
        SessionStatus status;
        uint256 startTime;
        uint256 endTime;
        uint256 questionCount;
        uint256 answeredCount;
        uint256 questionFee;
        bool isPaid;
    }

    struct Question {
        uint256 id;
        uint256 sessionId;
        address asker;
        string content;
        string answer;
        QuestionStatus status;
        uint256 upvotes;
        uint256 timestamp;
        uint256 answeredAt;
        bool isAnonymous;
    }

    Counters.Counter private _sessionIdCounter;
    Counters.Counter private _questionIdCounter;
    mapping(uint256 => AMASession) public sessions;
    mapping(uint256 => Question) public questions;
    mapping(uint256 => uint256[]) public sessionQuestions;
    mapping(address => uint256[]) public hostSessions;
    mapping(uint256 => mapping(address => bool)) public hasUpvoted;

    uint256 public constant SESSION_CREATION_FEE = 0.00001 ether;
    uint256 public constant MAX_QUESTION_LENGTH = 500;
    uint256 public constant MAX_ANSWER_LENGTH = 2000;

    constructor() {
        _sessionIdCounter.increment();
        _questionIdCounter.increment();
    }

    function createSession(
        string memory _title,
        string memory _description,
        string memory _topic,
        uint256 _startTime,
        uint256 _duration,
        uint256 _questionFee
    ) external payable nonReentrant returns (uint256) {
        require(msg.value >= SESSION_CREATION_FEE, "Insufficient fee");
        require(bytes(_title).length > 0, "Title required");
        require(_startTime >= block.timestamp, "Invalid start time");

        uint256 sessionId = _sessionIdCounter.current();
        _sessionIdCounter.increment();

        sessions[sessionId] = AMASession({
            id: sessionId,
            host: msg.sender,
            title: _title,
            description: _description,
            topic: _topic,
            status: SessionStatus.Scheduled,
            startTime: _startTime,
            endTime: _startTime + _duration,
            questionCount: 0,
            answeredCount: 0,
            questionFee: _questionFee,
            isPaid: _questionFee > 0
        });

        hostSessions[msg.sender].push(sessionId);
        emit AMASessionCreated(sessionId, msg.sender, block.timestamp);
        return sessionId;
    }

    function startSession(uint256 _sessionId) external {
        AMASession storage session = sessions[_sessionId];
        require(session.host == msg.sender, "Only host");
        require(session.status == SessionStatus.Scheduled, "Cannot start");
        session.status = SessionStatus.Live;
    }

    function endSession(uint256 _sessionId) external {
        AMASession storage session = sessions[_sessionId];
        require(session.host == msg.sender, "Only host");
        require(session.status == SessionStatus.Live, "Not live");
        session.status = SessionStatus.Ended;
    }

    function askQuestion(
        uint256 _sessionId,
        string memory _content,
        bool _isAnonymous
    ) external payable nonReentrant returns (uint256) {
        AMASession storage session = sessions[_sessionId];
        require(session.status != SessionStatus.Ended, "Session ended");
        require(bytes(_content).length > 0, "Empty question");
        require(bytes(_content).length <= MAX_QUESTION_LENGTH, "Too long");

        if (session.isPaid) {
            require(msg.value >= session.questionFee, "Insufficient fee");
        }

        uint256 questionId = _questionIdCounter.current();
        _questionIdCounter.increment();

        questions[questionId] = Question({
            id: questionId,
            sessionId: _sessionId,
            asker: msg.sender,
            content: _content,
            answer: "",
            status: QuestionStatus.Pending,
            upvotes: 0,
            timestamp: block.timestamp,
            answeredAt: 0,
            isAnonymous: _isAnonymous
        });

        sessionQuestions[_sessionId].push(questionId);
        session.questionCount++;

        emit QuestionAsked(_sessionId, questionId, msg.sender, block.timestamp);
        return questionId;
    }

    function answerQuestion(uint256 _questionId, string memory _answer) external nonReentrant {
        Question storage question = questions[_questionId];
        AMASession storage session = sessions[question.sessionId];
        
        require(session.host == msg.sender, "Only host");
        require(question.status == QuestionStatus.Pending, "Already answered");
        require(bytes(_answer).length > 0, "Empty answer");
        require(bytes(_answer).length <= MAX_ANSWER_LENGTH, "Too long");

        question.answer = _answer;
        question.status = QuestionStatus.Answered;
        question.answeredAt = block.timestamp;
        session.answeredCount++;

        emit QuestionAnswered(question.sessionId, _questionId, block.timestamp);
    }

    function upvoteQuestion(uint256 _questionId) external nonReentrant {
        require(!hasUpvoted[_questionId][msg.sender], "Already upvoted");
        
        questions[_questionId].upvotes++;
        hasUpvoted[_questionId][msg.sender] = true;

        emit QuestionUpvoted(_questionId, msg.sender, block.timestamp);
    }

    function getSession(uint256 _sessionId) external view returns (AMASession memory) {
        return sessions[_sessionId];
    }

    function getQuestion(uint256 _questionId) external view returns (Question memory) {
        return questions[_questionId];
    }

    function getSessionQuestions(uint256 _sessionId) external view returns (uint256[] memory) {
        return sessionQuestions[_sessionId];
    }

    function getHostSessions(address _host) external view returns (uint256[] memory) {
        return hostSessions[_host];
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
