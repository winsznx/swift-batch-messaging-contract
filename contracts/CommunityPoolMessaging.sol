// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CommunityPoolMessaging
 * @dev Community-funded messaging pools for subsidized communication
 * @author Swift v2 Team
 */
contract CommunityPoolMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event PoolCreated(
        uint256 indexed poolId,
        address indexed creator,
        string name,
        uint256 timestamp
    );

    event PoolFunded(
        uint256 indexed poolId,
        address indexed funder,
        uint256 amount,
        uint256 timestamp
    );

    event SubsidizedMessageSent(
        uint256 indexed messageId,
        uint256 indexed poolId,
        address indexed sender,
        address[] recipients,
        uint256 subsidyUsed,
        uint256 timestamp
    );

    // Structs
    struct CommunityPool {
        uint256 id;
        string name;
        string description;
        address creator;
        uint256 totalFunds; // in cUSD
        uint256 usedFunds;
        uint256 subsidyPerMessage;
        uint256 createdAt;
        bool isActive;
        address[] funders;
        mapping(address => uint256) contributions;
    }

    struct SubsidizedMessage {
        uint256 id;
        uint256 poolId;
        address sender;
        address[] recipients;
        string content;
        uint256 subsidyUsed;
        uint256 timestamp;
    }

    // State variables
    Counters.Counter private _poolIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => CommunityPool) public communityPools;
    mapping(uint256 => SubsidizedMessage) public subsidizedMessages;
    mapping(address => uint256[]) public userPools;
    mapping(address => uint256[]) public userMessages;

    // Celo cUSD address
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_POOL_CONTRIBUTION = 1000000000000000; // 0.001 cUSD
    uint256 public constant DEFAULT_SUBSIDY = 500000000000000; // 0.0005 cUSD

    constructor() {
        _poolIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create community pool
     * @param _name Pool name
     * @param _description Pool description
     * @param _subsidyPerMessage Subsidy amount per message
     * @param _initialFunding Initial funding amount
     */
    function createCommunityPool(
        string memory _name,
        string memory _description,
        uint256 _subsidyPerMessage,
        uint256 _initialFunding
    ) 
        external 
        nonReentrant 
    {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(_subsidyPerMessage > 0, "Subsidy must be greater than 0");
        require(_initialFunding >= MIN_POOL_CONTRIBUTION, "Initial funding too small");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        
        uint256 poolId = _poolIdCounter.current();
        _poolIdCounter.increment();

        CommunityPool storage pool = communityPools[poolId];
        pool.id = poolId;
        pool.name = _name;
        pool.description = _description;
        pool.creator = msg.sender;
        pool.subsidyPerMessage = _subsidyPerMessage;
        pool.createdAt = block.timestamp;
        pool.isActive = true;
        pool.totalFunds = _initialFunding;
        pool.usedFunds = 0;

        pool.funders.push(msg.sender);
        pool.contributions[msg.sender] = _initialFunding;

        // Transfer initial funding
        require(
            cusd.transferFrom(msg.sender, address(this), _initialFunding),
            "Funding transfer failed"
        );

        userPools[msg.sender].push(poolId);

        emit PoolCreated(poolId, msg.sender, _name, block.timestamp);
        emit PoolFunded(poolId, msg.sender, _initialFunding, block.timestamp);
    }

    /**
     * @dev Fund community pool
     * @param _poolId ID of the pool
     * @param _amount Amount to contribute
     */
    function fundPool(uint256 _poolId, uint256 _amount) 
        external 
        nonReentrant 
    {
        CommunityPool storage pool = communityPools[_poolId];
        require(pool.isActive, "Pool not active");
        require(_amount >= MIN_POOL_CONTRIBUTION, "Amount too small");
        
        IERC20 cusd = IERC20(CUSD_ADDRESS);

        if (pool.contributions[msg.sender] == 0) {
            pool.funders.push(msg.sender);
        }

        pool.contributions[msg.sender] += _amount;
        pool.totalFunds += _amount;

        require(
            cusd.transferFrom(msg.sender, address(this), _amount),
            "Funding transfer failed"
        );

        emit PoolFunded(_poolId, msg.sender, _amount, block.timestamp);
    }

    /**
     * @dev Send subsidized message
     * @param _poolId ID of the pool
     * @param _recipients Array of recipients
     * @param _content Message content
     */
    function sendSubsidizedMessage(
        uint256 _poolId,
        address[] memory _recipients,
        string memory _content
    ) 
        external 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        CommunityPool storage pool = communityPools[_poolId];
        require(pool.isActive, "Pool not active");
        
        uint256 availableFunds = pool.totalFunds - pool.usedFunds;
        require(availableFunds >= pool.subsidyPerMessage, "Insufficient pool funds");

        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        SubsidizedMessage storage message = subsidizedMessages[messageId];
        message.id = messageId;
        message.poolId = _poolId;
        message.sender = msg.sender;
        message.content = _content;
        message.subsidyUsed = pool.subsidyPerMessage;
        message.timestamp = block.timestamp;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        // Deduct subsidy from pool
        pool.usedFunds += pool.subsidyPerMessage;

        userMessages[msg.sender].push(messageId);

        emit SubsidizedMessageSent(
            messageId,
            _poolId,
            msg.sender,
            message.recipients,
            pool.subsidyPerMessage,
            block.timestamp
        );
    }

    /**
     * @dev Toggle pool active status
     * @param _poolId ID of the pool
     */
    function togglePoolStatus(uint256 _poolId) 
        external 
    {
        CommunityPool storage pool = communityPools[_poolId];
        require(pool.creator == msg.sender, "Only creator can toggle");
        
        pool.isActive = !pool.isActive;
    }

    /**
     * @dev Get pool details
     */
    function getPool(uint256 _poolId) 
        external 
        view 
        returns (
            uint256 id,
            string memory name,
            string memory description,
            address creator,
            uint256 totalFunds,
            uint256 usedFunds,
            uint256 subsidyPerMessage,
            uint256 createdAt,
            bool isActive
        )
    {
        CommunityPool storage pool = communityPools[_poolId];
        return (
            pool.id,
            pool.name,
            pool.description,
            pool.creator,
            pool.totalFunds,
            pool.usedFunds,
            pool.subsidyPerMessage,
            pool.createdAt,
            pool.isActive
        );
    }

    /**
     * @dev Get pool funders
     */
    function getPoolFunders(uint256 _poolId) 
        external 
        view 
        returns (address[] memory)
    {
        return communityPools[_poolId].funders;
    }

    /**
     * @dev Get user contribution to pool
     */
    function getUserContribution(uint256 _poolId, address _user) 
        external 
        view 
        returns (uint256)
    {
        return communityPools[_poolId].contributions[_user];
    }

    /**
     * @dev Get subsidized message details
     */
    function getSubsidizedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 poolId,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 subsidyUsed,
            uint256 timestamp
        )
    {
        SubsidizedMessage storage message = subsidizedMessages[_messageId];
        return (
            message.id,
            message.poolId,
            message.sender,
            message.recipients,
            message.content,
            message.subsidyUsed,
            message.timestamp
        );
    }

    /**
     * @dev Get user's pools
     */
    function getUserPools(address _user) external view returns (uint256[] memory) {
        return userPools[_user];
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw() external onlyOwner nonReentrant {
        IERC20 cusd = IERC20(CUSD_ADDRESS);
        uint256 balance = cusd.balanceOf(address(this));
        require(balance > 0, "No balance");

        require(cusd.transfer(owner(), balance), "Withdraw failed");
    }
}
