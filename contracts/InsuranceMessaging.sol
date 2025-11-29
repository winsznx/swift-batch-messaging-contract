// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title InsuranceMessaging
 * @dev Insurance claim messaging with coverage verification
 * @author Swift v2 Team
 */
contract InsuranceMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum ClaimStatus { SUBMITTED, UNDER_REVIEW, APPROVED, REJECTED, PAID }

    // Events
    event PolicyCreated(
        uint256 indexed policyId,
        address indexed holder,
        uint256 coverageAmount,
        uint256 timestamp
    );

    event ClaimSubmitted(
        uint256 indexed claimId,
        uint256 indexed policyId,
        address indexed claimant,
        uint256 amount,
        uint256 timestamp
    );

    event ClaimProcessed(
        uint256 indexed claimId,
        ClaimStatus status,
        uint256 timestamp
    );

    // Structs
    struct InsurancePolicy {
        uint256 id;
        address holder;
        uint256 coverageAmount;
        uint256 premium;
        uint256 startDate;
        uint256 expiryDate;
        bool isActive;
    }

    struct InsuranceClaim {
        uint256 id;
        uint256 policyId;
        address claimant;
        uint256 amount;
        string description;
        string evidence; // IPFS URL
        uint256 submittedAt;
        ClaimStatus status;
        string reviewNotes;
    }

    // State variables
    Counters.Counter private _policyIdCounter;
    Counters.Counter private _claimIdCounter;
    mapping(uint256 => InsurancePolicy) public policies;
    mapping(uint256 => InsuranceClaim) public claims;
    mapping(address => uint256[]) public userPolicies;
    mapping(address => uint256[]) public userClaims;

    // Constants
    uint256 public constant MIN_COVERAGE = 1 ether;
    uint256 public constant MAX_COVERAGE = 100 ether;
    uint256 public constant POLICY_DURATION = 31536000; // 1 year
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;

    constructor() {
        _policyIdCounter.increment();
        _claimIdCounter.increment();
    }

    /**
     * @dev Create insurance policy
     * @param _coverageAmount Coverage amount
     */
    function createPolicy(uint256 _coverageAmount) 
        external 
        payable 
        nonReentrant 
    {
        require(_coverageAmount >= MIN_COVERAGE, "Coverage too low");
        require(_coverageAmount <= MAX_COVERAGE, "Coverage too high");
        
        uint256 premium = (_coverageAmount * 5) / 100; // 5% premium
        require(msg.value >= premium, "Insufficient premium payment");
        
        uint256 policyId = _policyIdCounter.current();
        _policyIdCounter.increment();

        InsurancePolicy storage policy = policies[policyId];
        policy.id = policyId;
        policy.holder = msg.sender;
        policy.coverageAmount = _coverageAmount;
        policy.premium = premium;
        policy.startDate = block.timestamp;
        policy.expiryDate = block.timestamp + POLICY_DURATION;
        policy.isActive = true;

        userPolicies[msg.sender].push(policyId);

        emit PolicyCreated(policyId, msg.sender, _coverageAmount, block.timestamp);
    }

    /**
     * @dev Submit insurance claim
     * @param _policyId Policy ID
     * @param _amount Claim amount
     * @param _description Claim description
     * @param _evidence IPFS evidence URL
     */
    function submitClaim(
        uint256 _policyId,
        uint256 _amount,
        string memory _description,
        string memory _evidence
    ) 
        external 
        nonReentrant 
    {
        InsurancePolicy storage policy = policies[_policyId];
        require(policy.holder == msg.sender, "Not policy holder");
        require(policy.isActive, "Policy not active");
        require(block.timestamp <= policy.expiryDate, "Policy expired");
        require(_amount <= policy.coverageAmount, "Exceeds coverage");
        require(bytes(_description).length > 0, "Description required");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        
        uint256 claimId = _claimIdCounter.current();
        _claimIdCounter.increment();

        InsuranceClaim storage claim = claims[claimId];
        claim.id = claimId;
        claim.policyId = _policyId;
        claim.claimant = msg.sender;
        claim.amount = _amount;
        claim.description = _description;
        claim.evidence = _evidence;
        claim.submittedAt = block.timestamp;
        claim.status = ClaimStatus.SUBMITTED;

        userClaims[msg.sender].push(claimId);

        emit ClaimSubmitted(claimId, _policyId, msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Process claim (only owner)
     * @param _claimId Claim ID
     * @param _approved Whether claim is approved
     * @param _reviewNotes Review notes
     */
    function processClaim(
        uint256 _claimId,
        bool _approved,
        string memory _reviewNotes
    ) 
        external 
        onlyOwner 
        nonReentrant 
    {
        InsuranceClaim storage claim = claims[_claimId];
        require(
            claim.status == ClaimStatus.SUBMITTED || 
            claim.status == ClaimStatus.UNDER_REVIEW,
            "Cannot process claim"
        );

        claim.reviewNotes = _reviewNotes;

        if (_approved) {
            claim.status = ClaimStatus.APPROVED;
            
            // Pay out claim
            require(address(this).balance >= claim.amount, "Insufficient funds");
            
            (bool success, ) = payable(claim.claimant).call{value: claim.amount}("");
            require(success, "Payout failed");
            
            claim.status = ClaimStatus.PAID;
        } else {
            claim.status = ClaimStatus.REJECTED;
        }

        emit ClaimProcessed(_claimId, claim.status, block.timestamp);
    }

    /**
     * @dev Set claim under review
     */
    function setClaimUnderReview(uint256 _claimId) 
        external 
        onlyOwner 
    {
        InsuranceClaim storage claim = claims[_claimId];
        require(claim.status == ClaimStatus.SUBMITTED, "Invalid status");
        
        claim.status = ClaimStatus.UNDER_REVIEW;
        emit ClaimProcessed(_claimId, claim.status, block.timestamp);
    }

    /**
     * @dev Get policy details
     */
    function getPolicy(uint256 _policyId) 
        external 
        view 
        returns (
            uint256 id,
            address holder,
            uint256 coverageAmount,
            uint256 premium,
            uint256 startDate,
            uint256 expiryDate,
            bool isActive
        )
    {
        InsurancePolicy storage policy = policies[_policyId];
        return (
            policy.id,
            policy.holder,
            policy.coverageAmount,
            policy.premium,
            policy.startDate,
            policy.expiryDate,
            policy.isActive
        );
    }

    /**
     * @dev Get claim details
     */
    function getClaim(uint256 _claimId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 policyId,
            address claimant,
            uint256 amount,
            string memory description,
            string memory evidence,
            uint256 submittedAt,
            ClaimStatus status,
            string memory reviewNotes
        )
    {
        InsuranceClaim storage claim = claims[_claimId];
        return (
            claim.id,
            claim.policyId,
            claim.claimant,
            claim.amount,
            claim.description,
            claim.evidence,
            claim.submittedAt,
            claim.status,
            claim.reviewNotes
        );
    }

    /**
     * @dev Get user's policies
     */
    function getUserPolicies(address _user) external view returns (uint256[] memory) {
        return userPolicies[_user];
    }

    /**
     * @dev Get user's claims
     */
    function getUserClaims(address _user) external view returns (uint256[] memory) {
        return userClaims[_user];
    }

    /**
     * @dev Fund insurance pool
     */
    function fundPool() external payable {
        require(msg.value > 0, "Must send value");
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
