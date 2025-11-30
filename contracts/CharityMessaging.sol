// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title CharityMessaging
 * @dev Charitable donation messaging with campaign management and transparency
 * @author Swift v2 Team
 */
contract CharityMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed organizer,
        string name,
        uint256 goalAmount,
        uint256 timestamp
    );

    event DonationReceived(
        uint256 indexed donationId,
        uint256 indexed campaignId,
        address indexed donor,
        uint256 amount,
        uint256 timestamp
    );

    event CampaignMessageSent(
        uint256 indexed messageId,
        uint256 indexed campaignId,
        address indexed sender,
        uint256 timestamp
    );

    event MilestoneReached(
        uint256 indexed campaignId,
        uint256 amount,
        uint256 timestamp
    );

    event FundsWithdrawn(
        uint256 indexed campaignId,
        uint256 amount,
        uint256 timestamp
    );

    // Enums
    enum CampaignStatus { Active, Completed, Cancelled }

    // Structs
    struct Campaign {
        uint256 id;
        address organizer;
        string name;
        string description;
        string category;
        uint256 goalAmount;
        uint256 raisedAmount;
        uint256 donorCount;
        uint256 deadline;
        CampaignStatus status;
        uint256 createdAt;
        bool isVerified;
        string proofHash;
    }

    struct Donation {
        uint256 id;
        uint256 campaignId;
        address donor;
        uint256 amount;
        uint256 timestamp;
        string message;
        bool isAnonymous;
        uint256 matchAmount;
    }

    struct CampaignMessage {
        uint256 id;
        uint256 campaignId;
        address sender;
        string content;
        uint256 timestamp;
        bool isUpdate;
        string attachmentHash;
    }

    struct DonorBadge {
        string name;
        uint256 minDonation;
        uint256 color;
    }

    // State variables
    Counters.Counter private _campaignIdCounter;
    Counters.Counter private _donationIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => Donation) public donations;
    mapping(uint256 => CampaignMessage) public campaignMessages;
    mapping(uint256 => uint256[]) public campaignDonations;
    mapping(uint256 => uint256[]) public campaignMessageList;
    mapping(address => uint256[]) public userCampaigns;
    mapping(address => uint256[]) public userDonations;
    mapping(address => uint256) public totalDonated;
    mapping(uint256 => mapping(address => bool)) public hasDonated;
    mapping(uint256 => uint256) public matchingPool;
    
    DonorBadge[] public donorBadges;

    // Constants
    uint256 public constant MIN_GOAL_AMOUNT = 0.01 ether;
    uint256 public constant MAX_NAME_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 2000;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 2;
    uint256 public constant MATCHING_MULTIPLIER = 2;

    constructor() {
        _campaignIdCounter.increment();
        _donationIdCounter.increment();
        _messageIdCounter.increment();
        _initializeDonorBadges();
    }

    /**
     * @dev Initialize donor badges
     */
    function _initializeDonorBadges() private {
        donorBadges.push(DonorBadge({
            name: "Bronze Supporter",
            minDonation: 0.01 ether,
            color: 0xCD7F32
        }));

        donorBadges.push(DonorBadge({
            name: "Silver Supporter",
            minDonation: 0.1 ether,
            color: 0xC0C0C0
        }));

        donorBadges.push(DonorBadge({
            name: "Gold Supporter",
            minDonation: 0.5 ether,
            color: 0xFFD700
        }));

        donorBadges.push(DonorBadge({
            name: "Platinum Supporter",
            minDonation: 1 ether,
            color: 0xE5E4E2
        }));
    }

    /**
     * @dev Create charity campaign
     */
    function createCampaign(
        string memory _name,
        string memory _description,
        string memory _category,
        uint256 _goalAmount,
        uint256 _duration
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        require(bytes(_name).length > 0 && bytes(_name).length <= MAX_NAME_LENGTH, "Invalid name");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_goalAmount >= MIN_GOAL_AMOUNT, "Goal too low");
        require(_duration >= 1 days && _duration <= 365 days, "Invalid duration");

        uint256 campaignId = _campaignIdCounter.current();
        _campaignIdCounter.increment();

        campaigns[campaignId] = Campaign({
            id: campaignId,
            organizer: msg.sender,
            name: _name,
            description: _description,
            category: _category,
            goalAmount: _goalAmount,
            raisedAmount: 0,
            donorCount: 0,
            deadline: block.timestamp + _duration,
            status: CampaignStatus.Active,
            createdAt: block.timestamp,
            isVerified: false,
            proofHash: ""
        });

        userCampaigns[msg.sender].push(campaignId);

        emit CampaignCreated(campaignId, msg.sender, _name, _goalAmount, block.timestamp);

        return campaignId;
    }

    /**
     * @dev Donate to campaign
     */
    function donate(
        uint256 _campaignId,
        string memory _message,
        bool _isAnonymous
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == CampaignStatus.Active, "Campaign not active");
        require(block.timestamp < campaign.deadline, "Campaign ended");
        require(msg.value > 0, "Donation must be > 0");

        uint256 platformFee = (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 donationAmount = msg.value - platformFee;

        // Check for matching funds
        uint256 matchAmount = 0;
        if (matchingPool[_campaignId] > 0) {
            matchAmount = donationAmount;
            if (matchAmount > matchingPool[_campaignId]) {
                matchAmount = matchingPool[_campaignId];
            }
            matchingPool[_campaignId] -= matchAmount;
        }

        uint256 totalContribution = donationAmount + matchAmount;

        uint256 donationId = _donationIdCounter.current();
        _donationIdCounter.increment();

        donations[donationId] = Donation({
            id: donationId,
            campaignId: _campaignId,
            donor: _isAnonymous ? address(0) : msg.sender,
            amount: donationAmount,
            timestamp: block.timestamp,
            message: _message,
            isAnonymous: _isAnonymous,
            matchAmount: matchAmount
        });

        campaign.raisedAmount += totalContribution;
        
        if (!hasDonated[_campaignId][msg.sender]) {
            hasDonated[_campaignId][msg.sender] = true;
            campaign.donorCount++;
        }

        campaignDonations[_campaignId].push(donationId);
        userDonations[msg.sender].push(donationId);
        totalDonated[msg.sender] += donationAmount;

        // Check if goal reached
        if (campaign.raisedAmount >= campaign.goalAmount) {
            campaign.status = CampaignStatus.Completed;
            emit MilestoneReached(_campaignId, campaign.goalAmount, block.timestamp);
        }

        emit DonationReceived(donationId, _campaignId, msg.sender, totalContribution, block.timestamp);

        return donationId;
    }

    /**
     * @dev Add matching funds to campaign
     */
    function addMatchingFunds(uint256 _campaignId) 
        external 
        payable 
        nonReentrant 
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.status == CampaignStatus.Active, "Campaign not active");
        require(msg.value > 0, "Amount must be > 0");

        matchingPool[_campaignId] += msg.value;
    }

    /**
     * @dev Send campaign message/update
     */
    function sendCampaignMessage(
        uint256 _campaignId,
        string memory _content,
        bool _isUpdate,
        string memory _attachmentHash
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Campaign storage campaign = campaigns[_campaignId];
        
        if (_isUpdate) {
            require(campaign.organizer == msg.sender, "Only organizer can post updates");
        } else {
            require(
                hasDonated[_campaignId][msg.sender] || campaign.organizer == msg.sender,
                "Must donate to message"
            );
        }

        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        campaignMessages[messageId] = CampaignMessage({
            id: messageId,
            campaignId: _campaignId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isUpdate: _isUpdate,
            attachmentHash: _attachmentHash
        });

        campaignMessageList[_campaignId].push(messageId);

        emit CampaignMessageSent(messageId, _campaignId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Withdraw campaign funds (organizer only)
     */
    function withdrawFunds(uint256 _campaignId, uint256 _amount) 
        external 
        nonReentrant 
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.organizer == msg.sender, "Only organizer can withdraw");
        require(campaign.raisedAmount >= _amount, "Insufficient funds");
        require(_amount > 0, "Amount must be > 0");

        campaign.raisedAmount -= _amount;

        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Withdrawal failed");

        emit FundsWithdrawn(_campaignId, _amount, block.timestamp);
    }

    /**
     * @dev Submit proof of fund usage
     */
    function submitProof(uint256 _campaignId, string memory _proofHash) 
        external 
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.organizer == msg.sender, "Only organizer can submit proof");
        require(bytes(_proofHash).length > 0, "Proof hash required");

        campaign.proofHash = _proofHash;
    }

    /**
     * @dev Cancel campaign and refund donors
     */
    function cancelCampaign(uint256 _campaignId) 
        external 
        nonReentrant 
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(campaign.organizer == msg.sender, "Only organizer can cancel");
        require(campaign.status == CampaignStatus.Active, "Campaign not active");

        campaign.status = CampaignStatus.Cancelled;

        // Note: In production, implement refund mechanism for donors
    }

    /**
     * @dev Get donor badge level
     */
    function getDonorBadge(address _donor) 
        external 
        view 
        returns (string memory badgeName, uint256 color) 
    {
        uint256 donated = totalDonated[_donor];
        
        for (uint256 i = donorBadges.length; i > 0; i--) {
            if (donated >= donorBadges[i - 1].minDonation) {
                return (donorBadges[i - 1].name, donorBadges[i - 1].color);
            }
        }
        
        return ("New Supporter", 0x808080);
    }

    /**
     * @dev Get campaign details
     */
    function getCampaign(uint256 _campaignId) 
        external 
        view 
        returns (
            uint256 id,
            address organizer,
            string memory name,
            string memory category,
            uint256 goalAmount,
            uint256 raisedAmount,
            uint256 donorCount,
            uint256 deadline,
            CampaignStatus status
        )
    {
        Campaign memory campaign = campaigns[_campaignId];
        return (
            campaign.id,
            campaign.organizer,
            campaign.name,
            campaign.category,
            campaign.goalAmount,
            campaign.raisedAmount,
            campaign.donorCount,
            campaign.deadline,
            campaign.status
        );
    }

    /**
     * @dev Get campaign progress percentage
     */
    function getCampaignProgress(uint256 _campaignId) 
        external 
        view 
        returns (uint256) 
    {
        Campaign memory campaign = campaigns[_campaignId];
        if (campaign.goalAmount == 0) {
            return 0;
        }
        return (campaign.raisedAmount * 100) / campaign.goalAmount;
    }

    /**
     * @dev Get campaign donations
     */
    function getCampaignDonations(uint256 _campaignId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return campaignDonations[_campaignId];
    }

    /**
     * @dev Get campaign messages
     */
    function getCampaignMessages(uint256 _campaignId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return campaignMessageList[_campaignId];
    }

    /**
     * @dev Get user's total donations
     */
    function getUserDonationTotal(address _user) 
        external 
        view 
        returns (uint256) 
    {
        return totalDonated[_user];
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
