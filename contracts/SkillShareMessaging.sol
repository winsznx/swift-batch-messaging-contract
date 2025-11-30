// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title SkillShareMessaging
 * @dev Decentralized skill-sharing marketplace with tutoring and consultation messaging
 * @author Swift v2 Team
 */
contract SkillShareMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event SkillListed(
        uint256 indexed skillId,
        address indexed expert,
        string skillName,
        uint256 hourlyRate,
        uint256 timestamp
    );

    event SessionBooked(
        uint256 indexed sessionId,
        uint256 indexed skillId,
        address indexed student,
        uint256 timestamp
    );

    event SessionCompleted(
        uint256 indexed sessionId,
        uint256 timestamp
    );

    event SessionReviewed(
        uint256 indexed sessionId,
        address indexed reviewer,
        uint8 rating,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        uint256 indexed sessionId,
        address indexed sender,
        uint256 timestamp
    );

    // Enums
    enum SessionStatus { Pending, Active, Completed, Cancelled, Disputed }

    // Structs
    struct Skill {
        uint256 id;
        address expert;
        string name;
        string description;
        string category;
        uint256 hourlyRate;
        uint256 totalSessions;
        uint256 totalRatings;
        uint256 averageRating;
        bool isActive;
        uint256 listedAt;
    }

    struct Session {
        uint256 id;
        uint256 skillId;
        address expert;
        address student;
        uint256 duration; // in hours
        uint256 totalCost;
        uint256 scheduledTime;
        uint256 completedAt;
        SessionStatus status;
        uint8 expertRating;
        uint8 studentRating;
        string expertReview;
        string studentReview;
    }

    struct SessionMessage {
        uint256 id;
        uint256 sessionId;
        address sender;
        string content;
        uint256 timestamp;
        bool isAttachment;
        string attachmentHash;
    }

    struct ExpertProfile {
        uint256 totalEarned;
        uint256 totalSessions;
        uint256 averageRating;
        uint256 totalRatings;
        uint256[] skills;
        bool isVerified;
    }

    // State variables
    Counters.Counter private _skillIdCounter;
    Counters.Counter private _sessionIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(uint256 => Skill) public skills;
    mapping(uint256 => Session) public sessions;
    mapping(uint256 => SessionMessage) public messages;
    mapping(uint256 => uint256[]) public sessionMessages;
    mapping(address => ExpertProfile) public expertProfiles;
    mapping(address => uint256[]) public userSessions;
    mapping(string => uint256[]) public categorySkills;
    mapping(uint256 => uint256) public sessionEscrow;

    // Constants
    uint256 public constant MIN_HOURLY_RATE = 0.001 ether;
    uint256 public constant MAX_HOURLY_RATE = 10 ether;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _skillIdCounter.increment();
        _sessionIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev List a new skill
     */
    function listSkill(
        string memory _name,
        string memory _description,
        string memory _category,
        uint256 _hourlyRate
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_hourlyRate >= MIN_HOURLY_RATE && _hourlyRate <= MAX_HOURLY_RATE, "Invalid rate");

        uint256 skillId = _skillIdCounter.current();
        _skillIdCounter.increment();

        skills[skillId] = Skill({
            id: skillId,
            expert: msg.sender,
            name: _name,
            description: _description,
            category: _category,
            hourlyRate: _hourlyRate,
            totalSessions: 0,
            totalRatings: 0,
            averageRating: 0,
            isActive: true,
            listedAt: block.timestamp
        });

        expertProfiles[msg.sender].skills.push(skillId);
        categorySkills[_category].push(skillId);

        emit SkillListed(skillId, msg.sender, _name, _hourlyRate, block.timestamp);

        return skillId;
    }

    /**
     * @dev Book a tutoring session
     */
    function bookSession(
        uint256 _skillId,
        uint256 _duration,
        uint256 _scheduledTime
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        Skill storage skill = skills[_skillId];
        require(skill.isActive, "Skill not active");
        require(skill.expert != msg.sender, "Cannot book own skill");
        require(_duration > 0 && _duration <= 8, "Invalid duration");
        require(_scheduledTime > block.timestamp, "Invalid schedule time");

        uint256 totalCost = skill.hourlyRate * _duration;
        require(msg.value >= totalCost, "Insufficient payment");

        uint256 sessionId = _sessionIdCounter.current();
        _sessionIdCounter.increment();

        sessions[sessionId] = Session({
            id: sessionId,
            skillId: _skillId,
            expert: skill.expert,
            student: msg.sender,
            duration: _duration,
            totalCost: totalCost,
            scheduledTime: _scheduledTime,
            completedAt: 0,
            status: SessionStatus.Pending,
            expertRating: 0,
            studentRating: 0,
            expertReview: "",
            studentReview: ""
        });

        sessionEscrow[sessionId] = totalCost;
        userSessions[msg.sender].push(sessionId);
        userSessions[skill.expert].push(sessionId);

        emit SessionBooked(sessionId, _skillId, msg.sender, block.timestamp);

        return sessionId;
    }

    /**
     * @dev Complete session
     */
    function completeSession(uint256 _sessionId) 
        external 
        nonReentrant 
    {
        Session storage session = sessions[_sessionId];
        require(session.expert == msg.sender, "Only expert can complete");
        require(session.status == SessionStatus.Pending || session.status == SessionStatus.Active, "Invalid status");
        require(block.timestamp >= session.scheduledTime, "Session not started");

        session.status = SessionStatus.Completed;
        session.completedAt = block.timestamp;

        // Release payment to expert
        uint256 platformFee = (session.totalCost * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 expertPayment = session.totalCost - platformFee;

        sessionEscrow[_sessionId] = 0;

        (bool success, ) = payable(session.expert).call{value: expertPayment}("");
        require(success, "Payment failed");

        // Update skill stats
        Skill storage skill = skills[session.skillId];
        skill.totalSessions++;

        // Update expert profile
        ExpertProfile storage profile = expertProfiles[session.expert];
        profile.totalEarned += expertPayment;
        profile.totalSessions++;

        emit SessionCompleted(_sessionId, block.timestamp);
    }

    /**
     * @dev Review session
     */
    function reviewSession(
        uint256 _sessionId,
        uint8 _rating,
        string memory _review
    ) 
        external 
        nonReentrant 
    {
        Session storage session = sessions[_sessionId];
        require(session.status == SessionStatus.Completed, "Session not completed");
        require(_rating >= 1 && _rating <= 5, "Rating must be 1-5");

        if (msg.sender == session.student) {
            require(session.studentRating == 0, "Already reviewed");
            session.studentRating = _rating;
            session.studentReview = _review;

            // Update skill rating
            Skill storage skill = skills[session.skillId];
            skill.totalRatings++;
            uint256 totalScore = skill.averageRating * (skill.totalRatings - 1);
            skill.averageRating = (totalScore + _rating) / skill.totalRatings;

            // Update expert profile
            ExpertProfile storage profile = expertProfiles[session.expert];
            profile.totalRatings++;
            totalScore = profile.averageRating * (profile.totalRatings - 1);
            profile.averageRating = (totalScore + _rating) / profile.totalRatings;

        } else if (msg.sender == session.expert) {
            require(session.expertRating == 0, "Already reviewed");
            session.expertRating = _rating;
            session.expertReview = _review;
        } else {
            revert("Not authorized");
        }

        emit SessionReviewed(_sessionId, msg.sender, _rating, block.timestamp);
    }

    /**
     * @dev Send message in session
     */
    function sendSessionMessage(
        uint256 _sessionId,
        string memory _content,
        bool _isAttachment,
        string memory _attachmentHash
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Session storage session = sessions[_sessionId];
        require(
            session.student == msg.sender || session.expert == msg.sender,
            "Not session participant"
        );
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        messages[messageId] = SessionMessage({
            id: messageId,
            sessionId: _sessionId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isAttachment: _isAttachment,
            attachmentHash: _attachmentHash
        });

        sessionMessages[_sessionId].push(messageId);

        emit MessageSent(messageId, _sessionId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Cancel session
     */
    function cancelSession(uint256 _sessionId) 
        external 
        nonReentrant 
    {
        Session storage session = sessions[_sessionId];
        require(session.student == msg.sender, "Only student can cancel");
        require(session.status == SessionStatus.Pending, "Cannot cancel");
        require(block.timestamp < session.scheduledTime - 1 hours, "Too late to cancel");

        session.status = SessionStatus.Cancelled;

        // Refund student
        uint256 refund = sessionEscrow[_sessionId];
        sessionEscrow[_sessionId] = 0;

        (bool success, ) = payable(session.student).call{value: refund}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Toggle skill active status
     */
    function toggleSkillStatus(uint256 _skillId) 
        external 
    {
        Skill storage skill = skills[_skillId];
        require(skill.expert == msg.sender, "Only expert can toggle");
        
        skill.isActive = !skill.isActive;
    }

    /**
     * @dev Get skill details
     */
    function getSkill(uint256 _skillId) 
        external 
        view 
        returns (
            uint256 id,
            address expert,
            string memory name,
            string memory description,
            string memory category,
            uint256 hourlyRate,
            uint256 totalSessions,
            uint256 averageRating,
            bool isActive
        )
    {
        Skill memory skill = skills[_skillId];
        return (
            skill.id,
            skill.expert,
            skill.name,
            skill.description,
            skill.category,
            skill.hourlyRate,
            skill.totalSessions,
            skill.averageRating,
            skill.isActive
        );
    }

    /**
     * @dev Get expert profile
     */
    function getExpertProfile(address _expert) 
        external 
        view 
        returns (
            uint256 totalEarned,
            uint256 totalSessions,
            uint256 averageRating,
            uint256[] memory skillIds
        )
    {
        ExpertProfile memory profile = expertProfiles[_expert];
        return (
            profile.totalEarned,
            profile.totalSessions,
            profile.averageRating,
            profile.skills
        );
    }

    /**
     * @dev Get session messages
     */
    function getSessionMessages(uint256 _sessionId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return sessionMessages[_sessionId];
    }

    /**
     * @dev Get category skills
     */
    function getCategorySkills(string memory _category) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return categorySkills[_category];
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
