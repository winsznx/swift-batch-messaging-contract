// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title QuizMessaging
 * @dev Interactive quiz-based messaging with rewards
 * @author Swift v2 Team
 */
contract QuizMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    event QuizCreated(uint256 indexed quizId, address indexed creator, uint256 prizePool, uint256 timestamp);
    event AnswerSubmitted(uint256 indexed quizId, address indexed participant, uint256 score, uint256 timestamp);
    event QuizEnded(uint256 indexed quizId, address indexed winner, uint256 prize, uint256 timestamp);

    enum QuizStatus { Active, Ended, Cancelled }

    struct Quiz {
        uint256 id;
        address creator;
        string title;
        string category;
        uint256 prizePool;
        uint256 entryFee;
        QuizStatus status;
        uint256 endTime;
        uint256 participantCount;
        address topScorer;
        uint256 topScore;
    }

    struct Participation {
        address participant;
        uint256 score;
        bool hasCompleted;
    }

    Counters.Counter private _quizIdCounter;
    mapping(uint256 => Quiz) public quizzes;
    mapping(uint256 => mapping(address => Participation)) public participations;
    mapping(uint256 => address[]) public quizParticipants;
    mapping(address => uint256[]) public userQuizzes;

    uint256 public constant QUIZ_CREATION_FEE = 0.00001 ether;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;

    constructor() {
        _quizIdCounter.increment();
    }

    function createQuiz(
        string memory _title,
        string memory _category,
        uint256 _entryFee,
        uint256 _duration
    ) external payable nonReentrant returns (uint256) {
        require(msg.value >= QUIZ_CREATION_FEE, "Insufficient fee");
        require(bytes(_title).length > 0, "Title cannot be empty");

        uint256 quizId = _quizIdCounter.current();
        _quizIdCounter.increment();

        quizzes[quizId] = Quiz({
            id: quizId,
            creator: msg.sender,
            title: _title,
            category: _category,
            prizePool: msg.value - QUIZ_CREATION_FEE,
            entryFee: _entryFee,
            status: QuizStatus.Active,
            endTime: block.timestamp + _duration,
            participantCount: 0,
            topScorer: address(0),
            topScore: 0
        });

        userQuizzes[msg.sender].push(quizId);
        emit QuizCreated(quizId, msg.sender, msg.value - QUIZ_CREATION_FEE, block.timestamp);
        return quizId;
    }

    function joinQuiz(uint256 _quizId) external payable nonReentrant {
        Quiz storage quiz = quizzes[_quizId];
        require(quiz.status == QuizStatus.Active, "Quiz not active");
        require(block.timestamp < quiz.endTime, "Quiz ended");
        require(msg.value >= quiz.entryFee, "Insufficient entry fee");

        quiz.prizePool += msg.value;
        quiz.participantCount++;

        participations[_quizId][msg.sender] = Participation({
            participant: msg.sender,
            score: 0,
            hasCompleted: false
        });

        quizParticipants[_quizId].push(msg.sender);
    }

    function submitScore(uint256 _quizId, uint256 _score) external nonReentrant {
        Quiz storage quiz = quizzes[_quizId];
        require(quiz.status == QuizStatus.Active, "Quiz not active");
        
        Participation storage p = participations[_quizId][msg.sender];
        require(!p.hasCompleted, "Already completed");

        p.score = _score;
        p.hasCompleted = true;

        if (_score > quiz.topScore) {
            quiz.topScore = _score;
            quiz.topScorer = msg.sender;
        }

        emit AnswerSubmitted(_quizId, msg.sender, _score, block.timestamp);
    }

    function endQuiz(uint256 _quizId) external nonReentrant {
        Quiz storage quiz = quizzes[_quizId];
        require(quiz.creator == msg.sender || block.timestamp >= quiz.endTime, "Cannot end");
        require(quiz.status == QuizStatus.Active, "Quiz not active");

        quiz.status = QuizStatus.Ended;

        if (quiz.topScorer != address(0) && quiz.prizePool > 0) {
            uint256 platformFee = (quiz.prizePool * PLATFORM_FEE_PERCENTAGE) / 100;
            uint256 winnerPrize = quiz.prizePool - platformFee;

            (bool success, ) = payable(quiz.topScorer).call{value: winnerPrize}("");
            require(success, "Prize transfer failed");

            emit QuizEnded(_quizId, quiz.topScorer, winnerPrize, block.timestamp);
        }
    }

    function getQuiz(uint256 _quizId) external view returns (Quiz memory) {
        return quizzes[_quizId];
    }

    function getQuizParticipants(uint256 _quizId) external view returns (address[] memory) {
        return quizParticipants[_quizId];
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
