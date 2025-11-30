// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title DisputeResolutionMessaging
 * @dev Decentralized dispute resolution with arbitration and evidence submission
 * @author Swift v2 Team
 */
contract DisputeResolutionMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event DisputeCreated(
        uint256 indexed disputeId,
        address indexed plaintiff,
        address indexed defendant,
        uint256 timestamp
    );

    event EvidenceSubmitted(
        uint256 indexed evidenceId,
        uint256 indexed disputeId,
        address indexed submitter,
        uint256 timestamp
    );

    event ArbitratorAssigned(
        uint256 indexed disputeId,
        address indexed arbitrator,
        uint256 timestamp
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        address indexed winner,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        uint256 indexed disputeId,
        address indexed sender,
        uint256 timestamp
    );

    // Enums
    enum DisputeStatus { Open, UnderReview, Resolved, Cancelled }
    enum Resolution { Pending, PlaintiffWins, DefendantWins, Draw }

    // Structs
    struct Dispute {
        uint256 id;
        address plaintiff;
        address defendant;
        string title;
        string description;
        uint256 stakeAmount;
        address arbitrator;
        DisputeStatus status;
        Resolution resolution;
        uint256 createdAt;
        uint256 resolvedAt;
        string resolutionReason;
    }

    struct Evidence {
        uint256 id;
        uint256 disputeId;
        address submitter;
        string description;
        string documentHash;
        uint256 timestamp;
        bool isValidated;
    }

    struct DisputeMessage {
        uint256 id;
        uint256 disputeId;
        address sender;
        string content;
        uint256 timestamp;
        bool isPrivate;
    }

    struct Arbitrator {
        address wallet;
        uint256 totalCases;
        uint256 resolvedCases;
        uint256 reputation;
        bool isActive;
        uint256 fee;
    }

    // State variables
    Counters.Counter private _disputeIdCounter;
    Counters.Counter private _evidenceIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => Evidence) public evidences;
    mapping(uint256 => DisputeMessage) public disputeMessages;
    mapping(uint256 => uint256[]) public disputeEvidenceList;
    mapping(uint256 => uint256[]) public disputeMessageList;
    mapping(address => uint256[]) public userDisputes;
    mapping(address => Arbitrator) public arbitrators;
    mapping(uint256 => mapping(address => uint256)) public disputeStakes;
    
    address[] public arbitratorList;

    // Constants
    uint256 public constant MIN_STAKE = 0.01 ether;
    uint256 public constant MAX_TITLE_LENGTH = 200;
    uint256 public constant MAX_DESCRIPTION_LENGTH = 1000;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant ARBITRATOR_FEE_PERCENTAGE = 10;

    constructor() {
        _disputeIdCounter.increment();
        _evidenceIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Register as arbitrator
     */
    function registerArbitrator(uint256 _fee) 
        external 
        nonReentrant 
    {
        require(!arbitrators[msg.sender].isActive, "Already registered");
        require(_fee > 0, "Invalid fee");

        arbitrators[msg.sender] = Arbitrator({
            wallet: msg.sender,
            totalCases: 0,
            resolvedCases: 0,
            reputation: 50,
            isActive: true,
            fee: _fee
        });

        arbitratorList.push(msg.sender);
    }

    /**
     * @dev Create new dispute
     */
    function createDispute(
        address _defendant,
        string memory _title,
        string memory _description,
        address _preferredArbitrator
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= MIN_STAKE, "Insufficient stake");
        require(_defendant != address(0), "Invalid defendant");
        require(_defendant != msg.sender, "Cannot dispute yourself");
        require(bytes(_title).length > 0 && bytes(_title).length <= MAX_TITLE_LENGTH, "Invalid title");
        require(bytes(_description).length <= MAX_DESCRIPTION_LENGTH, "Description too long");

        uint256 disputeId = _disputeIdCounter.current();
        _disputeIdCounter.increment();

        address arbitrator = _preferredArbitrator;
        if (arbitrator == address(0) || !arbitrators[arbitrator].isActive) {
            arbitrator = _selectRandomArbitrator();
        }

        disputes[disputeId] = Dispute({
            id: disputeId,
            plaintiff: msg.sender,
            defendant: _defendant,
            title: _title,
            description: _description,
            stakeAmount: msg.value,
            arbitrator: arbitrator,
            status: DisputeStatus.Open,
            resolution: Resolution.Pending,
            createdAt: block.timestamp,
            resolvedAt: 0,
            resolutionReason: ""
        });

        disputeStakes[disputeId][msg.sender] = msg.value;
        userDisputes[msg.sender].push(disputeId);
        userDisputes[_defendant].push(disputeId);

        if (arbitrator != address(0)) {
            arbitrators[arbitrator].totalCases++;
            emit ArbitratorAssigned(disputeId, arbitrator, block.timestamp);
        }

        emit DisputeCreated(disputeId, msg.sender, _defendant, block.timestamp);

        return disputeId;
    }

    /**
     * @dev Defendant stakes to accept dispute
     */
    function acceptDispute(uint256 _disputeId) 
        external 
        payable 
        nonReentrant 
    {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.defendant == msg.sender, "Only defendant can accept");
        require(dispute.status == DisputeStatus.Open, "Dispute not open");
        require(msg.value >= dispute.stakeAmount, "Match plaintiff stake");

        disputeStakes[_disputeId][msg.sender] = msg.value;
        dispute.status = DisputeStatus.UnderReview;
    }

    /**
     * @dev Submit evidence
     */
    function submitEvidence(
        uint256 _disputeId,
        string memory _description,
        string memory _documentHash
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Dispute storage dispute = disputes[_disputeId];
        require(
            dispute.plaintiff == msg.sender || dispute.defendant == msg.sender,
            "Not dispute party"
        );
        require(dispute.status == DisputeStatus.UnderReview, "Dispute not under review");
        require(bytes(_description).length > 0, "Empty description");

        uint256 evidenceId = _evidenceIdCounter.current();
        _evidenceIdCounter.increment();

        evidences[evidenceId] = Evidence({
            id: evidenceId,
            disputeId: _disputeId,
            submitter: msg.sender,
            description: _description,
            documentHash: _documentHash,
            timestamp: block.timestamp,
            isValidated: false
        });

        disputeEvidenceList[_disputeId].push(evidenceId);

        emit EvidenceSubmitted(evidenceId, _disputeId, msg.sender, block.timestamp);

        return evidenceId;
    }

    /**
     * @dev Send dispute message
     */
    function sendDisputeMessage(
        uint256 _disputeId,
        string memory _content,
        bool _isPrivate
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Dispute storage dispute = disputes[_disputeId];
        require(
            dispute.plaintiff == msg.sender || 
            dispute.defendant == msg.sender ||
            dispute.arbitrator == msg.sender,
            "Not authorized"
        );
        require(dispute.status != DisputeStatus.Cancelled, "Dispute cancelled");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        disputeMessages[messageId] = DisputeMessage({
            id: messageId,
            disputeId: _disputeId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isPrivate: _isPrivate
        });

        disputeMessageList[_disputeId].push(messageId);

        emit MessageSent(messageId, _disputeId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Resolve dispute (arbitrator only)
     */
    function resolveDispute(
        uint256 _disputeId,
        Resolution _resolution,
        string memory _reason
    ) 
        external 
        nonReentrant 
    {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.arbitrator == msg.sender, "Only assigned arbitrator");
        require(dispute.status == DisputeStatus.UnderReview, "Not under review");
        require(_resolution != Resolution.Pending, "Must provide resolution");

        dispute.status = DisputeStatus.Resolved;
        dispute.resolution = _resolution;
        dispute.resolvedAt = block.timestamp;
        dispute.resolutionReason = _reason;

        uint256 totalStake = disputeStakes[_disputeId][dispute.plaintiff] + 
                            disputeStakes[_disputeId][dispute.defendant];
        uint256 arbitratorFee = (totalStake * ARBITRATOR_FEE_PERCENTAGE) / 100;
        uint256 winnerAmount = totalStake - arbitratorFee;

        address winner;
        
        if (_resolution == Resolution.PlaintiffWins) {
            winner = dispute.plaintiff;
            (bool success, ) = payable(winner).call{value: winnerAmount}("");
            require(success, "Transfer failed");
        } else if (_resolution == Resolution.DefendantWins) {
            winner = dispute.defendant;
            (bool success, ) = payable(winner).call{value: winnerAmount}("");
            require(success, "Transfer failed");
        } else if (_resolution == Resolution.Draw) {
            // Split stakes back to both parties
            uint256 refund = (totalStake - arbitratorFee) / 2;
            (bool success1, ) = payable(dispute.plaintiff).call{value: refund}("");
            (bool success2, ) = payable(dispute.defendant).call{value: refund}("");
            require(success1 && success2, "Refund failed");
            winner = address(0);
        }

        // Pay arbitrator
        (bool success, ) = payable(dispute.arbitrator).call{value: arbitratorFee}("");
        require(success, "Arbitrator payment failed");

        arbitrators[dispute.arbitrator].resolvedCases++;
        arbitrators[dispute.arbitrator].reputation += 5;

        emit DisputeResolved(_disputeId, winner, block.timestamp);
    }

    /**
     * @dev Cancel dispute (only before accepted)
     */
    function cancelDispute(uint256 _disputeId) 
        external 
        nonReentrant 
    {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.plaintiff == msg.sender, "Only plaintiff can cancel");
        require(dispute.status == DisputeStatus.Open, "Can only cancel open disputes");

        dispute.status = DisputeStatus.Cancelled;

        // Refund plaintiff stake
        uint256 refund = disputeStakes[_disputeId][msg.sender];
        disputeStakes[_disputeId][msg.sender] = 0;

        (bool success, ) = payable(msg.sender).call{value: refund}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Select random arbitrator from active pool
     */
    function _selectRandomArbitrator() 
        private 
        view 
        returns (address) 
    {
        if (arbitratorList.length == 0) {
            return address(0);
        }

        uint256 randomIndex = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.difficulty,
            msg.sender
        ))) % arbitratorList.length;

        address selected = arbitratorList[randomIndex];
        
        if (arbitrators[selected].isActive) {
            return selected;
        }

        return address(0);
    }

    /**
     * @dev Get dispute details
     */
    function getDispute(uint256 _disputeId) 
        external 
        view 
        returns (
            uint256 id,
            address plaintiff,
            address defendant,
            string memory title,
            address arbitrator,
            DisputeStatus status,
            Resolution resolution,
            uint256 stakeAmount
        )
    {
        Dispute memory dispute = disputes[_disputeId];
        return (
            dispute.id,
            dispute.plaintiff,
            dispute.defendant,
            dispute.title,
            dispute.arbitrator,
            dispute.status,
            dispute.resolution,
            dispute.stakeAmount
        );
    }

    /**
     * @dev Get dispute evidence
     */
    function getDisputeEvidence(uint256 _disputeId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return disputeEvidenceList[_disputeId];
    }

    /**
     * @dev Get dispute messages
     */
    function getDisputeMessages(uint256 _disputeId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return disputeMessageList[_disputeId];
    }

    /**
     * @dev Get arbitrator info
     */
    function getArbitrator(address _arbitrator) 
        external 
        view 
        returns (
            uint256 totalCases,
            uint256 resolvedCases,
            uint256 reputation,
            bool isActive,
            uint256 fee
        )
    {
        Arbitrator memory arb = arbitrators[_arbitrator];
        return (
            arb.totalCases,
            arb.resolvedCases,
            arb.reputation,
            arb.isActive,
            arb.fee
        );
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
