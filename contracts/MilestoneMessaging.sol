// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title MilestoneMessaging
 * @dev Project milestone-based messaging with payment releases
 * @author Swift v2 Team
 */
contract MilestoneMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ProjectCreated(
        uint256 indexed projectId,
        address indexed client,
        address indexed contractor,
        uint256 totalBudget,
        uint256 timestamp
    );

    event MilestoneCompleted(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        uint256 timestamp
    );

    event MilestoneApproved(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        uint256 paymentAmount,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        uint256 indexed projectId,
        address indexed sender,
        uint256 timestamp
    );

    event DisputeRaised(
        uint256 indexed projectId,
        uint256 indexed milestoneIndex,
        address raisedBy,
        uint256 timestamp
    );

    // Enums
    enum ProjectStatus { Active, Completed, Disputed, Cancelled }
    enum MilestoneStatus { Pending, InProgress, Completed, Approved, Disputed }

    // Structs
    struct Milestone {
        string title;
        string description;
        uint256 paymentAmount;
        uint256 deadline;
        MilestoneStatus status;
        uint256 completedAt;
        uint256 approvedAt;
    }

    struct Project {
        uint256 id;
        address client;
        address contractor;
        string title;
        string description;
        uint256 totalBudget;
        uint256 paidAmount;
        ProjectStatus status;
        uint256 createdAt;
        Milestone[] milestones;
        uint256 completedMilestones;
    }

    struct ProjectMessage {
        uint256 id;
        uint256 projectId;
        address sender;
        string content;
        string attachmentHash;
        uint256 timestamp;
        uint256 milestoneRef;
    }

    // State variables
    Counters.Counter private _projectIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => Project) public projects;
    mapping(uint256 => ProjectMessage) public messages;
    mapping(uint256 => uint256[]) public projectMessages;
    mapping(address => uint256[]) public clientProjects;
    mapping(address => uint256[]) public contractorProjects;

    // Constants
    uint256 public constant MAX_MILESTONES = 20;
    uint256 public constant MAX_TITLE_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 2000;
    uint256 public constant MAX_MESSAGE_LENGTH = 1000;
    uint256 public constant PROJECT_CREATION_FEE = 0.00001 ether;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 2;

    constructor() {
        _projectIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create project with milestones
     */
    function createProject(
        address _contractor,
        string memory _title,
        string memory _description,
        string[] memory _milestoneTitles,
        string[] memory _milestoneDescriptions,
        uint256[] memory _milestonePayments,
        uint256[] memory _milestoneDeadlines
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(_contractor != address(0), "Invalid contractor");
        require(_contractor != msg.sender, "Cannot be own contractor");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(_milestoneTitles.length > 0, "Need at least 1 milestone");
        require(_milestoneTitles.length <= MAX_MILESTONES, "Too many milestones");
        require(
            _milestoneTitles.length == _milestoneDescriptions.length &&
            _milestoneTitles.length == _milestonePayments.length &&
            _milestoneTitles.length == _milestoneDeadlines.length,
            "Array length mismatch"
        );

        uint256 totalBudget = PROJECT_CREATION_FEE;
        for (uint256 i = 0; i < _milestonePayments.length; i++) {
            totalBudget += _milestonePayments[i];
        }
        require(msg.value >= totalBudget, "Insufficient funds");

        uint256 projectId = _projectIdCounter.current();
        _projectIdCounter.increment();

        Project storage project = projects[projectId];
        project.id = projectId;
        project.client = msg.sender;
        project.contractor = _contractor;
        project.title = _title;
        project.description = _description;
        project.totalBudget = msg.value - PROJECT_CREATION_FEE;
        project.paidAmount = 0;
        project.status = ProjectStatus.Active;
        project.createdAt = block.timestamp;
        project.completedMilestones = 0;

        for (uint256 i = 0; i < _milestoneTitles.length; i++) {
            project.milestones.push(Milestone({
                title: _milestoneTitles[i],
                description: _milestoneDescriptions[i],
                paymentAmount: _milestonePayments[i],
                deadline: _milestoneDeadlines[i],
                status: MilestoneStatus.Pending,
                completedAt: 0,
                approvedAt: 0
            }));
        }

        clientProjects[msg.sender].push(projectId);
        contractorProjects[_contractor].push(projectId);

        emit ProjectCreated(projectId, msg.sender, _contractor, project.totalBudget, block.timestamp);

        return projectId;
    }

    /**
     * @dev Mark milestone as completed (contractor)
     */
    function completeMilestone(
        uint256 _projectId,
        uint256 _milestoneIndex,
        string memory _completionNote
    ) 
        external 
        nonReentrant 
    {
        Project storage project = projects[_projectId];
        require(project.contractor == msg.sender, "Only contractor");
        require(project.status == ProjectStatus.Active, "Project not active");
        require(_milestoneIndex < project.milestones.length, "Invalid milestone");
        
        Milestone storage milestone = project.milestones[_milestoneIndex];
        require(
            milestone.status == MilestoneStatus.Pending || 
            milestone.status == MilestoneStatus.InProgress,
            "Cannot complete"
        );

        milestone.status = MilestoneStatus.Completed;
        milestone.completedAt = block.timestamp;

        // Send completion message
        _sendMessage(_projectId, _completionNote, "", _milestoneIndex);

        emit MilestoneCompleted(_projectId, _milestoneIndex, block.timestamp);
    }

    /**
     * @dev Approve milestone and release payment (client)
     */
    function approveMilestone(
        uint256 _projectId,
        uint256 _milestoneIndex
    ) 
        external 
        nonReentrant 
    {
        Project storage project = projects[_projectId];
        require(project.client == msg.sender, "Only client");
        require(project.status == ProjectStatus.Active, "Project not active");
        require(_milestoneIndex < project.milestones.length, "Invalid milestone");
        
        Milestone storage milestone = project.milestones[_milestoneIndex];
        require(milestone.status == MilestoneStatus.Completed, "Not completed");

        milestone.status = MilestoneStatus.Approved;
        milestone.approvedAt = block.timestamp;
        project.completedMilestones++;

        // Calculate and transfer payment
        uint256 platformFee = (milestone.paymentAmount * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 contractorPayment = milestone.paymentAmount - platformFee;
        project.paidAmount += milestone.paymentAmount;

        (bool success, ) = payable(project.contractor).call{value: contractorPayment}("");
        require(success, "Payment failed");

        // Check if project is complete
        if (project.completedMilestones == project.milestones.length) {
            project.status = ProjectStatus.Completed;
        }

        emit MilestoneApproved(_projectId, _milestoneIndex, contractorPayment, block.timestamp);
    }

    /**
     * @dev Raise dispute on milestone
     */
    function raiseMilestoneDispute(
        uint256 _projectId,
        uint256 _milestoneIndex,
        string memory _reason
    ) 
        external 
        nonReentrant 
    {
        Project storage project = projects[_projectId];
        require(
            project.client == msg.sender || project.contractor == msg.sender,
            "Not authorized"
        );
        require(project.status == ProjectStatus.Active, "Project not active");
        
        Milestone storage milestone = project.milestones[_milestoneIndex];
        milestone.status = MilestoneStatus.Disputed;
        project.status = ProjectStatus.Disputed;

        _sendMessage(_projectId, _reason, "", _milestoneIndex);

        emit DisputeRaised(_projectId, _milestoneIndex, msg.sender, block.timestamp);
    }

    /**
     * @dev Send project message
     */
    function sendProjectMessage(
        uint256 _projectId,
        string memory _content,
        string memory _attachmentHash,
        uint256 _milestoneRef
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Project storage project = projects[_projectId];
        require(
            project.client == msg.sender || project.contractor == msg.sender,
            "Not authorized"
        );
        require(bytes(_content).length > 0, "Empty message");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Message too long");

        return _sendMessage(_projectId, _content, _attachmentHash, _milestoneRef);
    }

    /**
     * @dev Internal send message
     */
    function _sendMessage(
        uint256 _projectId,
        string memory _content,
        string memory _attachmentHash,
        uint256 _milestoneRef
    ) 
        internal 
        returns (uint256)
    {
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        messages[messageId] = ProjectMessage({
            id: messageId,
            projectId: _projectId,
            sender: msg.sender,
            content: _content,
            attachmentHash: _attachmentHash,
            timestamp: block.timestamp,
            milestoneRef: _milestoneRef
        });

        projectMessages[_projectId].push(messageId);

        emit MessageSent(messageId, _projectId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Get project details
     */
    function getProject(uint256 _projectId) 
        external 
        view 
        returns (
            uint256 id,
            address client,
            address contractor,
            string memory title,
            uint256 totalBudget,
            uint256 paidAmount,
            ProjectStatus status,
            uint256 milestoneCount,
            uint256 completedMilestones
        )
    {
        Project storage project = projects[_projectId];
        return (
            project.id,
            project.client,
            project.contractor,
            project.title,
            project.totalBudget,
            project.paidAmount,
            project.status,
            project.milestones.length,
            project.completedMilestones
        );
    }

    /**
     * @dev Get milestone details
     */
    function getMilestone(uint256 _projectId, uint256 _milestoneIndex)
        external
        view
        returns (
            string memory title,
            string memory description,
            uint256 paymentAmount,
            uint256 deadline,
            MilestoneStatus status,
            uint256 completedAt,
            uint256 approvedAt
        )
    {
        Project storage project = projects[_projectId];
        require(_milestoneIndex < project.milestones.length, "Invalid milestone");
        
        Milestone storage milestone = project.milestones[_milestoneIndex];
        return (
            milestone.title,
            milestone.description,
            milestone.paymentAmount,
            milestone.deadline,
            milestone.status,
            milestone.completedAt,
            milestone.approvedAt
        );
    }

    /**
     * @dev Get project messages
     */
    function getProjectMessages(uint256 _projectId) external view returns (uint256[] memory) {
        return projectMessages[_projectId];
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
