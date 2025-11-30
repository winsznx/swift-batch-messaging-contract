// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title BountyMessaging
 * @dev Bounty-based messaging where tasks and rewards are offered for responses
 * @author Swift v2 Team
 */
contract BountyMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event BountyCreated(
        uint256 indexed bountyId,
        address indexed creator,
        uint256 reward,
        uint256 timestamp
    );

    event ResponseSubmitted(
        uint256 indexed responseId,
        uint256 indexed bountyId,
        address indexed responder,
        uint256 timestamp
    );

    event BountyAwarded(
        uint256 indexed bountyId,
        uint256 indexed responseId,
        address indexed winner,
        uint256 reward,
        uint256 timestamp
    );

    event BountyCancelled(
        uint256 indexed bountyId,
        uint256 timestamp
    );

    // Enums
    enum BountyStatus { Active, Awarded, Cancelled, Expired }
    enum ResponseStatus { Pending, Accepted, Rejected }

    // Structs
    struct Bounty {
        uint256 id;
        address creator;
        string task;
        string category;
        uint256 reward;
        uint256 maxResponses;
        uint256 deadline;
        BountyStatus status;
        uint256 createdAt;
        uint256 responseCount;
        uint256 winningResponseId;
        bool allowMultipleWinners;
        uint256 winnersCount;
    }

    struct Response {
        uint256 id;
        uint256 bountyId;
        address responder;
        string content;
        uint256 timestamp;
        ResponseStatus status;
        uint256 upvotes;
        mapping(address => bool) hasVoted;
    }

    // State variables
    Counters.Counter private _bountyIdCounter;
    Counters.Counter private _responseIdCounter;
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => Response) public responses;
    mapping(uint256 => uint256[]) public bountyResponses;
    mapping(address => uint256[]) public userBounties;
    mapping(address => uint256[]) public userResponses;
    mapping(string => uint256[]) public categoryBounties;

    // Constants
    uint256 public constant MIN_BOUNTY_REWARD = 0.0001 ether;
    uint256 public constant MAX_TASK_LENGTH = 1000;
    uint256 public constant MAX_RESPONSE_LENGTH = 2000;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 2;

    constructor() {
        _bountyIdCounter.increment();
        _responseIdCounter.increment();
    }

    /**
     * @dev Create new bounty
     */
    function createBounty(
        string memory _task,
        string memory _category,
        uint256 _maxResponses,
        uint256 _duration,
        bool _allowMultipleWinners
    ) 
        external 
        payable 
        nonReentrant 
        returns (uint256)
    {
        require(msg.value >= MIN_BOUNTY_REWARD, "Reward too low");
        require(bytes(_task).length > 0, "Task cannot be empty");
        require(bytes(_task).length <= MAX_TASK_LENGTH, "Task too long");
        require(_maxResponses > 0, "Invalid max responses");
        require(_duration >= 1 hours && _duration <= 30 days, "Invalid duration");

        uint256 bountyId = _bountyIdCounter.current();
        _bountyIdCounter.increment();

        bounties[bountyId] = Bounty({
            id: bountyId,
            creator: msg.sender,
            task: _task,
            category: _category,
            reward: msg.value,
            maxResponses: _maxResponses,
            deadline: block.timestamp + _duration,
            status: BountyStatus.Active,
            createdAt: block.timestamp,
            responseCount: 0,
            winningResponseId: 0,
            allowMultipleWinners: _allowMultipleWinners,
            winnersCount: 0
        });

        userBounties[msg.sender].push(bountyId);
        categoryBounties[_category].push(bountyId);

        emit BountyCreated(bountyId, msg.sender, msg.value, block.timestamp);

        return bountyId;
    }

    /**
     * @dev Submit response to bounty
     */
    function submitResponse(
        uint256 _bountyId,
        string memory _content
    ) 
        external 
        nonReentrant 
        returns (uint256)
    {
        Bounty storage bounty = bounties[_bountyId];
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(block.timestamp < bounty.deadline, "Bounty expired");
        require(bounty.responseCount < bounty.maxResponses, "Max responses reached");
        require(bounty.creator != msg.sender, "Cannot respond to own bounty");
        require(bytes(_content).length > 0, "Empty response");
        require(bytes(_content).length <= MAX_RESPONSE_LENGTH, "Response too long");

        uint256 responseId = _responseIdCounter.current();
        _responseIdCounter.increment();

        Response storage response = responses[responseId];
        response.id = responseId;
        response.bountyId = _bountyId;
        response.responder = msg.sender;
        response.content = _content;
        response.timestamp = block.timestamp;
        response.status = ResponseStatus.Pending;
        response.upvotes = 0;

        bountyResponses[_bountyId].push(responseId);
        userResponses[msg.sender].push(responseId);
        bounty.responseCount++;

        emit ResponseSubmitted(responseId, _bountyId, msg.sender, block.timestamp);

        return responseId;
    }

    /**
     * @dev Award bounty to winner
     */
    function awardBounty(
        uint256 _bountyId,
        uint256 _responseId
    ) 
        external 
        nonReentrant 
    {
        Bounty storage bounty = bounties[_bountyId];
        Response storage response = responses[_responseId];

        require(bounty.creator == msg.sender, "Only creator can award");
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(response.bountyId == _bountyId, "Response not for this bounty");
        require(response.status == ResponseStatus.Pending, "Response already processed");

        response.status = ResponseStatus.Accepted;

        uint256 platformFee = (bounty.reward * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 winnerReward;

        if (bounty.allowMultipleWinners) {
            // Split reward among winners
            winnerReward = (bounty.reward - platformFee) / bounty.maxResponses;
            bounty.winnersCount++;

            if (bounty.winnersCount >= bounty.maxResponses) {
                bounty.status = BountyStatus.Awarded;
            }
        } else {
            winnerReward = bounty.reward - platformFee;
            bounty.status = BountyStatus.Awarded;
            bounty.winningResponseId = _responseId;
        }

        (bool success, ) = payable(response.responder).call{value: winnerReward}("");
        require(success, "Transfer failed");

        emit BountyAwarded(_bountyId, _responseId, response.responder, winnerReward, block.timestamp);
    }

    /**
     * @dev Cancel bounty and refund creator
     */
    function cancelBounty(uint256 _bountyId) 
        external 
        nonReentrant 
    {
        Bounty storage bounty = bounties[_bountyId];
        require(bounty.creator == msg.sender, "Only creator can cancel");
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(bounty.responseCount == 0, "Cannot cancel with responses");

        bounty.status = BountyStatus.Cancelled;

        (bool success, ) = payable(msg.sender).call{value: bounty.reward}("");
        require(success, "Refund failed");

        emit BountyCancelled(_bountyId, block.timestamp);
    }

    /**
     * @dev Upvote a response
     */
    function upvoteResponse(uint256 _responseId) 
        external 
        nonReentrant 
    {
        Response storage response = responses[_responseId];
        require(response.id != 0, "Response doesn't exist");
        require(!response.hasVoted[msg.sender], "Already voted");
        require(response.status == ResponseStatus.Pending, "Response not pending");

        response.hasVoted[msg.sender] = true;
        response.upvotes++;
    }

    /**
     * @dev Expire bounty if deadline passed
     */
    function expireBounty(uint256 _bountyId) 
        external 
        nonReentrant 
    {
        Bounty storage bounty = bounties[_bountyId];
        require(bounty.status == BountyStatus.Active, "Bounty not active");
        require(block.timestamp >= bounty.deadline, "Deadline not reached");

        bounty.status = BountyStatus.Expired;

        // Refund creator
        (bool success, ) = payable(bounty.creator).call{value: bounty.reward}("");
        require(success, "Refund failed");
    }

    /**
     * @dev Get bounty details
     */
    function getBounty(uint256 _bountyId) 
        external 
        view 
        returns (
            uint256 id,
            address creator,
            string memory task,
            string memory category,
            uint256 reward,
            uint256 deadline,
            BountyStatus status,
            uint256 responseCount,
            uint256 winnersCount
        )
    {
        Bounty memory bounty = bounties[_bountyId];
        return (
            bounty.id,
            bounty.creator,
            bounty.task,
            bounty.category,
            bounty.reward,
            bounty.deadline,
            bounty.status,
            bounty.responseCount,
            bounty.winnersCount
        );
    }

    /**
     * @dev Get response details
     */
    function getResponse(uint256 _responseId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 bountyId,
            address responder,
            string memory content,
            uint256 timestamp,
            ResponseStatus status,
            uint256 upvotes
        )
    {
        Response storage response = responses[_responseId];
        return (
            response.id,
            response.bountyId,
            response.responder,
            response.content,
            response.timestamp,
            response.status,
            response.upvotes
        );
    }

    /**
     * @dev Get bounty responses
     */
    function getBountyResponses(uint256 _bountyId) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return bountyResponses[_bountyId];
    }

    /**
     * @dev Get user's bounties
     */
    function getUserBounties(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userBounties[_user];
    }

    /**
     * @dev Get category bounties
     */
    function getCategoryBounties(string memory _category) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return categoryBounties[_category];
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
