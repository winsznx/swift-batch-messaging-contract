// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title DAO_Messaging
 * @dev Decentralized Autonomous Organization messaging with proposal discussions
 * @author Swift v2 Team
 */
contract DAO_Messaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event DAOCreated(
        uint256 indexed daoId,
        address indexed creator,
        string name,
        uint256 timestamp
    );

    event MemberJoined(
        uint256 indexed daoId,
        address indexed member,
        uint256 timestamp
    );

    event ProposalCreated(
        uint256 indexed proposalId,
        uint256 indexed daoId,
        address indexed proposer,
        uint256 timestamp
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support,
        uint256 weight,
        uint256 timestamp
    );

    event MessageSent(
        uint256 indexed messageId,
        uint256 indexed daoId,
        address indexed sender,
        uint256 timestamp
    );

    // Enums
    enum ProposalStatus { Active, Passed, Rejected, Executed, Cancelled }
    enum VoteType { Against, For, Abstain }

    // Structs
    struct DAO {
        uint256 id;
        address creator;
        string name;
        string description;
        uint256 memberCount;
        uint256 proposalCount;
        uint256 treasuryBalance;
        uint256 votingPeriod;
        uint256 quorumPercentage;
        uint256 createdAt;
        bool isActive;
    }

    struct Member {
        address wallet;
        uint256 joinedAt;
        uint256 votingPower;
        uint256 proposalsCreated;
        uint256 votesParticipated;
        bool isActive;
    }

    struct Proposal {
        uint256 id;
        uint256 daoId;
        address proposer;
        string title;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 createdAt;
        uint256 votingEnds;
        ProposalStatus status;
        bytes executionData;
    }

    struct Vote {
        address voter;
        VoteType voteType;
        uint256 weight;
        uint256 timestamp;
        string reason;
    }

    struct DAOMessage {
        uint256 id;
        uint256 daoId;
        uint256 proposalId;
        address sender;
        string content;
        uint256 timestamp;
        bool isPinned;
        uint256 upvotes;
    }

    // State variables
    Counters.Counter private _daoIdCounter;
    Counters.Counter private _proposalIdCounter;
    Counters.Counter private _messageIdCounter;
    
    mapping(uint256 => DAO) public daos;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => DAOMessage) public daoMessages;
    mapping(uint256 => mapping(address => Member)) public daoMembers;
    mapping(uint256 => address[]) public daoMemberList;
    mapping(uint256 => uint256[]) public daoProposals;
    mapping(uint256 => uint256[]) public daoMessageList;
    mapping(uint256 => mapping(uint256 => uint256[])) public proposalMessages;
    mapping(uint256 => mapping(address => Vote)) public proposalVotes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(address => uint256[]) public userDAOs;

    // Constants
    uint256 public constant DAO_CREATION_FEE = 0.001 ether;
    uint256 public constant MIN_VOTING_PERIOD = 1 days;
    uint256 public constant MAX_VOTING_PERIOD = 30 days;
    uint256 public constant DEFAULT_QUORUM = 10; // 10%
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;

    constructor() {
        _daoIdCounter.increment();
        _proposalIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create new DAO
     */
    function createDAO(
        string memory _name,
        string memory _description,
        uint256 _votingPeriod,
        uint256 _quorumPercentage
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= DAO_CREATION_FEE, "Insufficient creation fee");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_votingPeriod >= MIN_VOTING_PERIOD && _votingPeriod <= MAX_VOTING_PERIOD, "Invalid voting period");
        require(_quorumPercentage > 0 && _quorumPercentage <= 100, "Invalid quorum");

        uint256 daoId = _daoIdCounter.current();
        _daoIdCounter.increment();

        daos[daoId] = DAO({
            id: daoId,
            creator: msg.sender,
            name: _name,
            description: _description,
            memberCount: 1,
            proposalCount: 0,
            treasuryBalance: 0,
            votingPeriod: _votingPeriod,
            quorumPercentage: _quorumPercentage,
            createdAt: block.timestamp,
            isActive: true
        });

        // Creator is first member
        daoMembers[daoId][msg.sender] = Member({
            wallet: msg.sender,
            joinedAt: block.timestamp,
            votingPower: 1,
            proposalsCreated: 0,
            votesParticipated: 0,
            isActive: true
        });

        daoMemberList[daoId].push(msg.sender);
        userDAOs[msg.sender].push(daoId);

        emit DAOCreated(daoId, msg.sender, _name, block.timestamp);

        return daoId;
    }

    /**
     * @dev Join DAO
     */
    function joinDAO(uint256 _daoId) 
        external 
        payable 
        nonReentrant 
    {
        DAO storage dao = daos[_daoId];
        require(dao.isActive, "DAO not active");
        require(!daoMembers[_daoId][msg.sender].isActive, "Already a member");

        daoMembers[_daoId][msg.sender] = Member({
            wallet: msg.sender,
            joinedAt: block.timestamp,
            votingPower: 1,
            proposalsCreated: 0,
            votesParticipated: 0,
            isActive: true
        });

        daoMemberList[_daoId].push(msg.sender);
        userDAOs[msg.sender].push(_daoId);
        dao.memberCount++;

        // Contribute to treasury if sent
        if (msg.value > 0) {
            dao.treasuryBalance += msg.value;
        }

        emit MemberJoined(_daoId, msg.sender, block.timestamp);
    }

    /**
     * @dev Create proposal
     */
    function createProposal(
        uint256 _daoId,
        string memory _title,
        string memory _description,
        bytes memory _executionData
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        DAO storage dao = daos[_daoId];
        require(dao.isActive, "DAO not active");
        require(daoMembers[_daoId][msg.sender].isActive, "Not a member");
        require(bytes(_title).length > 0, "Title cannot be empty");

        uint256 proposalId = _proposalIdCounter.current();
        _proposalIdCounter.increment();

        proposals[proposalId] = Proposal({
            id: proposalId,
            daoId: _daoId,
            proposer: msg.sender,
            title: _title,
            description: _description,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            createdAt: block.timestamp,
            votingEnds: block.timestamp + dao.votingPeriod,
            status: ProposalStatus.Active,
            executionData: _executionData
        });

        daoProposals[_daoId].push(proposalId);
        dao.proposalCount++;
        daoMembers[_daoId][msg.sender].proposalsCreated++;

        emit ProposalCreated(proposalId, _daoId, msg.sender, block.timestamp);

        return proposalId;
    }

    /**
     * @dev Cast vote on proposal
     */
    function castVote(
        uint256 _proposalId,
        VoteType _voteType,
        string memory _reason
    ) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp < proposal.votingEnds, "Voting ended");
        require(!hasVoted[_proposalId][msg.sender], "Already voted");
        
        Member storage member = daoMembers[proposal.daoId][msg.sender];
        require(member.isActive, "Not a member");

        uint256 weight = member.votingPower;

        proposalVotes[_proposalId][msg.sender] = Vote({
            voter: msg.sender,
            voteType: _voteType,
            weight: weight,
            timestamp: block.timestamp,
            reason: _reason
        });

        hasVoted[_proposalId][msg.sender] = true;
        member.votesParticipated++;

        if (_voteType == VoteType.For) {
            proposal.forVotes += weight;
        } else if (_voteType == VoteType.Against) {
            proposal.againstVotes += weight;
        } else {
            proposal.abstainVotes += weight;
        }

        emit VoteCast(_proposalId, msg.sender, _voteType == VoteType.For, weight, block.timestamp);
    }

    /**
     * @dev Send DAO message
     */
    function sendDAOMessage(
        uint256 _daoId,
        uint256 _proposalId,
        string memory _content
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        require(daoMembers[_daoId][msg.sender].isActive, "Not a member");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        daoMessages[messageId] = DAOMessage({
            id: messageId,
            daoId: _daoId,
            proposalId: _proposalId,
            sender: msg.sender,
            content: _content,
            timestamp: block.timestamp,
            isPinned: false,
            upvotes: 0
        });

        daoMessageList[_daoId].push(messageId);

        if (_proposalId != 0) {
            proposalMessages[_daoId][_proposalId].push(messageId);
        }

        emit MessageSent(messageId, _daoId, msg.sender, block.timestamp);

        return messageId;
    }

    /**
     * @dev Finalize proposal
     */
    function finalizeProposal(uint256 _proposalId) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.Active, "Proposal not active");
        require(block.timestamp >= proposal.votingEnds, "Voting not ended");

        DAO storage dao = daos[proposal.daoId];
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 quorumRequired = (dao.memberCount * dao.quorumPercentage) / 100;

        if (totalVotes >= quorumRequired && proposal.forVotes > proposal.againstVotes) {
            proposal.status = ProposalStatus.Passed;
        } else {
            proposal.status = ProposalStatus.Rejected;
        }
    }

    /**
     * @dev Execute passed proposal
     */
    function executeProposal(uint256 _proposalId) 
        external 
        nonReentrant 
    {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.status == ProposalStatus.Passed, "Proposal not passed");
        
        proposal.status = ProposalStatus.Executed;
        
        // Execution logic would go here
        // This is a simplified version
    }

    /**
     * @dev Contribute to DAO treasury
     */
    function contributeTreasury(uint256 _daoId) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value > 0, "Amount must be > 0");
        daos[_daoId].treasuryBalance += msg.value;
    }

    /**
     * @dev Get DAO details
     */
    function getDAO(uint256 _daoId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            string memory name,
            uint256 memberCount,
            uint256 proposalCount,
            uint256 treasuryBalance,
            bool isActive
        )
    {
        DAO memory dao = daos[_daoId];
        return (
            dao.id,
            dao.creator,
            dao.name,
            dao.memberCount,
            dao.proposalCount,
            dao.treasuryBalance,
            dao.isActive
        );
    }

    /**
     * @dev Get proposal details
     */
    function getProposal(uint256 _proposalId) 
        external 
        view 
        returns (
            uint256 id,
            string memory title,
            address proposer,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 abstainVotes,
            uint256 votingEnds,
            ProposalStatus status
        )
    {
        Proposal memory proposal = proposals[_proposalId];
        return (
            proposal.id,
            proposal.title,
            proposal.proposer,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.votingEnds,
            proposal.status
        );
    }

    /**
     * @dev Get DAO members
     */
    function getDAOMembers(uint256 _daoId) 
        external 
        view 
        returns (address[] memory) 
    {
        return daoMemberList[_daoId];
    }

    /**
     * @dev Get DAO proposals
     */
    function getDAOProposals(uint256 _daoId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return daoProposals[_daoId];
    }

    /**
     * @dev Get proposal messages
     */
    function getProposalMessages(uint256 _daoId, uint256 _proposalId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return proposalMessages[_daoId][_proposalId];
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
