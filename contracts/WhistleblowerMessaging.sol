// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title WhistleblowerMessaging
 * @dev Anonymous reporting system with rewards and verification
 * @author Swift v2 Team
 */
contract WhistleblowerMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event ReportSubmitted(
        uint256 indexed reportId,
        bytes32 contentHash,
        string category,
        uint256 timestamp
    );

    event ReportVerified(
        uint256 indexed reportId,
        address indexed verifier,
        bool isValid,
        uint256 rewardAmount
    );

    event RewardClaimed(
        uint256 indexed reportId,
        address indexed claimant,
        uint256 amount
    );

    // Structs
    struct Report {
        uint256 id;
        address submitter; // Can be a temporary address for anonymity
        bytes32 contentHash; // Hash of the report content (stored off-chain or encrypted)
        string category;
        string publicData; // Non-sensitive data
        bool isVerified;
        bool isValid;
        uint256 rewardAmount;
        bool rewardClaimed;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _reportIdCounter;
    mapping(uint256 => Report) public reports;
    mapping(address => bool) public verifiers;
    
    uint256 public constant MIN_REWARD_POOL = 0.1 ether;

    constructor() {
        _reportIdCounter.increment();
        verifiers[msg.sender] = true; // Owner is default verifier
    }

    modifier onlyVerifier() {
        require(verifiers[msg.sender], "Not a verifier");
        _;
    }

    /**
     * @dev Submit a new report
     * @param _contentHash Hash of the sensitive content
     * @param _category Category of the report
     * @param _publicData Any public metadata
     */
    function submitReport(
        bytes32 _contentHash,
        string memory _category,
        string memory _publicData
    ) external nonReentrant {
        uint256 reportId = _reportIdCounter.current();
        _reportIdCounter.increment();

        Report storage report = reports[reportId];
        report.id = reportId;
        report.submitter = msg.sender;
        report.contentHash = _contentHash;
        report.category = _category;
        report.publicData = _publicData;
        report.timestamp = block.timestamp;

        emit ReportSubmitted(reportId, _contentHash, _category, block.timestamp);
    }

    /**
     * @dev Verify a report and assign reward
     * @param _reportId Report ID
     * @param _isValid Whether the report is valid
     * @param _rewardAmount Reward amount in wei
     */
    function verifyReport(
        uint256 _reportId,
        bool _isValid,
        uint256 _rewardAmount
    ) external payable onlyVerifier nonReentrant {
        Report storage report = reports[_reportId];
        require(report.id != 0, "Report does not exist");
        require(!report.isVerified, "Already verified");

        if (_rewardAmount > 0) {
            require(msg.value >= _rewardAmount, "Insufficient reward funding");
        }

        report.isVerified = true;
        report.isValid = _isValid;
        report.rewardAmount = _rewardAmount;

        emit ReportVerified(_reportId, msg.sender, _isValid, _rewardAmount);
    }

    /**
     * @dev Claim reward for a valid report
     */
    function claimReward(uint256 _reportId) external nonReentrant {
        Report storage report = reports[_reportId];
        require(report.submitter == msg.sender, "Not submitter");
        require(report.isVerified, "Not verified");
        require(report.isValid, "Report not valid");
        require(!report.rewardClaimed, "Reward already claimed");
        require(report.rewardAmount > 0, "No reward assigned");

        report.rewardClaimed = true;

        (bool success, ) = payable(msg.sender).call{value: report.rewardAmount}("");
        require(success, "Transfer failed");

        emit RewardClaimed(_reportId, msg.sender, report.rewardAmount);
    }

    /**
     * @dev Add or remove a verifier
     */
    function setVerifier(address _verifier, bool _status) external onlyOwner {
        verifiers[_verifier] = _status;
    }

    /**
     * @dev Get report details
     */
    function getReport(uint256 _reportId) external view returns (
        address submitter,
        bytes32 contentHash,
        string memory category,
        bool isVerified,
        bool isValid,
        uint256 rewardAmount,
        bool rewardClaimed,
        uint256 timestamp
    ) {
        Report storage report = reports[_reportId];
        return (
            report.submitter,
            report.contentHash,
            report.category,
            report.isVerified,
            report.isValid,
            report.rewardAmount,
            report.rewardClaimed,
            report.timestamp
        );
    }
}
