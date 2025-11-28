// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title SocialImpactMessaging
 * @dev Track and verify social impact claims with on-chain proof
 * @author Swift v2 Team
 */
contract SocialImpactMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum ImpactCategory { EDUCATION, HEALTHCARE, ENVIRONMENT, POVERTY, EQUALITY, OTHER }

    // Events
    event ImpactMessageCreated(
        uint256 indexed impactId,
        address indexed creator,
        ImpactCategory category,
        uint256 timestamp
    );

    event ImpactVerified(
        uint256 indexed impactId,
        address indexed verifier,
        uint256 timestamp
    );

    event ImpactEndorsed(
        uint256 indexed impactId,
        address indexed endorser,
        uint256 timestamp
    );

    // Structs
    struct ImpactMessage {
        uint256 id;
        address creator;
        string title;
        string description;
        ImpactCategory category;
        string proofUrl; // IPFS URL to proof documents
        uint256 peopleImpacted;
        uint256 timestamp;
        address[] verifiers;
        mapping(address => bool) hasVerified;
        address[] endorsers;
        mapping(address => bool) hasEndorsed;
        uint256 endorsementCount;
        bool isVerified;
    }

    // State variables
    Counters.Counter private _impactIdCounter;
    mapping(uint256 => ImpactMessage) public impactMessages;
    mapping(address => uint256[]) public userImpacts;
    mapping(address => bool) public approvedVerifiers;
    mapping(address => uint256) public userImpactScore; // Reputation score

    // Constants
    uint256 public constant MAX_TITLE_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 public constant VERIFICATION_THRESHOLD = 2;
    uint256 public constant IMPACT_CREATION_FEE = 0.00001 ether;

    constructor() {
        _impactIdCounter.increment();
    }

    /**
     * @dev Add approved verifier
     */
    function addVerifier(address _verifier) external onlyOwner {
        require(_verifier != address(0), "Invalid verifier");
        approvedVerifiers[_verifier] = true;
    }

    /**
     * @dev Remove verifier
     */
    function removeVerifier(address _verifier) external onlyOwner {
        approvedVerifiers[_verifier] = false;
    }

    /**
     * @dev Create social impact message
     * @param _title Impact title
     * @param _description Impact description
     * @param _category Impact category
     * @param _proofUrl IPFS URL to proof
     * @param _peopleImpacted Number of people impacted
     */
    function createImpactMessage(
        string memory _title,
        string memory _description,
        ImpactCategory _category,
        string memory _proofUrl,
        uint256 _peopleImpacted
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= IMPACT_CREATION_FEE, "Insufficient fee");
        require(bytes(_title).length > 0, "Title cannot be empty");
        require(bytes(_title).length <= MAX_TITLE_LENGTH, "Title too long");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");
        require(_peopleImpacted > 0, "Must impact at least 1 person");
        
        uint256 impactId = _impactIdCounter.current();
        _impactIdCounter.increment();

        ImpactMessage storage impact = impactMessages[impactId];
        impact.id = impactId;
        impact.creator = msg.sender;
        impact.title = _title;
        impact.description = _description;
        impact.category = _category;
        impact.proofUrl = _proofUrl;
        impact.peopleImpacted = _peopleImpacted;
        impact.timestamp = block.timestamp;
        impact.endorsementCount = 0;
        impact.isVerified = false;

        userImpacts[msg.sender].push(impactId);

        emit ImpactMessageCreated(
            impactId,
            msg.sender,
            _category,
            block.timestamp
        );
    }

    /**
     * @dev Verify impact (approved verifiers only)
     * @param _impactId ID of the impact
     */
    function verifyImpact(uint256 _impactId) 
        external 
        nonReentrant 
    {
        require(approvedVerifiers[msg.sender], "Not an approved verifier");
        
        ImpactMessage storage impact = impactMessages[_impactId];
        require(!impact.hasVerified[msg.sender], "Already verified");

        impact.hasVerified[msg.sender] = true;
        impact.verifiers.push(msg.sender);

        // If threshold reached, mark as verified
        if (impact.verifiers.length >= VERIFICATION_THRESHOLD) {
            impact.isVerified = true;
            // Reward creator with impact score
            userImpactScore[impact.creator] += impact.peopleImpacted;
        }

        emit ImpactVerified(_impactId, msg.sender, block.timestamp);
    }

    /**
     * @dev Endorse impact (anyone can endorse)
     * @param _impactId ID of the impact
     */
    function endorseImpact(uint256 _impactId) 
        external 
        nonReentrant 
    {
        ImpactMessage storage impact = impactMessages[_impactId];
        require(!impact.hasEndorsed[msg.sender], "Already endorsed");

        impact.hasEndorsed[msg.sender] = true;
        impact.endorsers.push(msg.sender);
        impact.endorsementCount++;

        emit ImpactEndorsed(_impactId, msg.sender, block.timestamp);
    }

    /**
     * @dev Get impact message details
     */
    function getImpactMessage(uint256 _impactId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            string memory title,
            string memory description,
            ImpactCategory category,
            string memory proofUrl,
            uint256 peopleImpacted,
            uint256 timestamp,
            uint256 verifierCount,
            uint256 endorsementCount,
            bool isVerified
        )
    {
        ImpactMessage storage impact = impactMessages[_impactId];
        return (
            impact.id,
            impact.creator,
            impact.title,
            impact.description,
            impact.category,
            impact.proofUrl,
            impact.peopleImpacted,
            impact.timestamp,
            impact.verifiers.length,
            impact.endorsementCount,
            impact.isVerified
        );
    }

    /**
     * @dev Get impact verifiers
     */
    function getImpactVerifiers(uint256 _impactId) 
        external 
        view 
        returns (address[] memory)
    {
        return impactMessages[_impactId].verifiers;
    }

    /**
     * @dev Get user's impacts
     */
    function getUserImpacts(address _user) external view returns (uint256[] memory) {
        return userImpacts[_user];
    }

    /**
     * @dev Get user's impact score
     */
    function getUserImpactScore(address _user) external view returns (uint256) {
        return userImpactScore[_user];
    }

    /**
     * @dev Check if user has endorsed
     */
    function hasEndorsed(uint256 _impactId, address _user) 
        external 
        view 
        returns (bool)
    {
        return impactMessages[_impactId].hasEndorsed[_user];
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
