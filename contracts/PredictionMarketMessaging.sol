// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title PredictionMarketMessaging
 * @dev Messaging-based prediction markets where users can bet on outcomes via messages
 * @author Swift v2 Team
 */
contract PredictionMarketMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MarketCreated(
        uint256 indexed marketId,
        address indexed creator,
        string question,
        uint256 deadline
    );

    event BetPlaced(
        uint256 indexed marketId,
        address indexed better,
        uint256 optionId,
        uint256 amount
    );

    event MarketResolved(
        uint256 indexed marketId,
        uint256 winningOptionId,
        address resolver
    );

    event WinningsClaimed(
        uint256 indexed marketId,
        address indexed user,
        uint256 amount
    );

    // Structs
    struct Market {
        uint256 id;
        address creator;
        string question;
        string[] options;
        uint256 deadline;
        uint256 totalPool;
        mapping(uint256 => uint256) optionPools;
        bool resolved;
        uint256 winningOptionId;
        bool cancelled;
    }

    struct Bet {
        uint256 amount;
        bool claimed;
    }

    // State variables
    Counters.Counter private _marketIdCounter;
    mapping(uint256 => Market) public markets;
    // marketId => user => optionId => Bet
    mapping(uint256 => mapping(address => mapping(uint256 => Bet))) public bets;
    
    uint256 public constant MIN_BET = 0.001 ether;
    uint256 public constant MARKET_FEE = 0.01 ether; // Fee to create a market

    constructor() {
        _marketIdCounter.increment();
    }

    /**
     * @dev Create a new prediction market
     * @param _question The question to be predicted
     * @param _options Possible outcomes
     * @param _duration Duration in seconds until the market closes
     */
    function createMarket(
        string memory _question,
        string[] memory _options,
        uint256 _duration
    ) external payable nonReentrant {
        require(msg.value >= MARKET_FEE, "Insufficient creation fee");
        require(bytes(_question).length > 0, "Question cannot be empty");
        require(_options.length > 1, "Must have at least 2 options");
        require(_duration > 0, "Duration must be positive");

        uint256 marketId = _marketIdCounter.current();
        _marketIdCounter.increment();

        Market storage market = markets[marketId];
        market.id = marketId;
        market.creator = msg.sender;
        market.question = _question;
        market.options = _options;
        market.deadline = block.timestamp + _duration;
        
        emit MarketCreated(marketId, msg.sender, _question, market.deadline);
    }

    /**
     * @dev Place a bet on a market option
     * @param _marketId The ID of the market
     * @param _optionId The index of the option to bet on
     */
    function placeBet(uint256 _marketId, uint256 _optionId) external payable nonReentrant {
        require(msg.value >= MIN_BET, "Bet amount too low");
        
        Market storage market = markets[_marketId];
        require(market.id != 0, "Market does not exist");
        require(block.timestamp < market.deadline, "Market closed");
        require(!market.resolved, "Market already resolved");
        require(!market.cancelled, "Market cancelled");
        require(_optionId < market.options.length, "Invalid option");

        market.totalPool += msg.value;
        market.optionPools[_optionId] += msg.value;

        Bet storage userBet = bets[_marketId][msg.sender][_optionId];
        userBet.amount += msg.value;

        emit BetPlaced(_marketId, msg.sender, _optionId, msg.value);
    }

    /**
     * @dev Resolve the market (only creator)
     * @param _marketId The ID of the market
     * @param _winningOptionId The index of the winning option
     */
    function resolveMarket(uint256 _marketId, uint256 _winningOptionId) external nonReentrant {
        Market storage market = markets[_marketId];
        require(msg.sender == market.creator, "Only creator can resolve");
        require(block.timestamp >= market.deadline, "Market not yet closed");
        require(!market.resolved, "Already resolved");
        require(!market.cancelled, "Market cancelled");
        require(_winningOptionId < market.options.length, "Invalid option");

        market.resolved = true;
        market.winningOptionId = _winningOptionId;

        emit MarketResolved(_marketId, _winningOptionId, msg.sender);
    }

    /**
     * @dev Claim winnings for a resolved market
     * @param _marketId The ID of the market
     */
    function claimWinnings(uint256 _marketId) external nonReentrant {
        Market storage market = markets[_marketId];
        require(market.resolved, "Market not resolved");
        
        uint256 winningOption = market.winningOptionId;
        Bet storage userBet = bets[_marketId][msg.sender][winningOption];
        
        require(userBet.amount > 0, "No bet on winning option");
        require(!userBet.claimed, "Already claimed");

        uint256 winningPool = market.optionPools[winningOption];
        uint256 reward = (userBet.amount * market.totalPool) / winningPool;

        userBet.claimed = true;
        
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "Transfer failed");

        emit WinningsClaimed(_marketId, msg.sender, reward);
    }

    /**
     * @dev Cancel market and allow refunds (only creator before resolution)
     */
    function cancelMarket(uint256 _marketId) external nonReentrant {
        Market storage market = markets[_marketId];
        require(msg.sender == market.creator, "Only creator can cancel");
        require(!market.resolved, "Already resolved");
        require(!market.cancelled, "Already cancelled");

        market.cancelled = true;
    }

    /**
     * @dev Refund bet for cancelled market
     */
    function refundBet(uint256 _marketId, uint256 _optionId) external nonReentrant {
        Market storage market = markets[_marketId];
        require(market.cancelled, "Market not cancelled");

        Bet storage userBet = bets[_marketId][msg.sender][_optionId];
        require(userBet.amount > 0, "No bet to refund");
        require(!userBet.claimed, "Already refunded");

        uint256 amount = userBet.amount;
        userBet.claimed = true;

        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /**
     * @dev Get market details
     */
    function getMarket(uint256 _marketId) external view returns (
        address creator,
        string memory question,
        string[] memory options,
        uint256 deadline,
        uint256 totalPool,
        bool resolved,
        uint256 winningOptionId,
        bool cancelled
    ) {
        Market storage market = markets[_marketId];
        return (
            market.creator,
            market.question,
            market.options,
            market.deadline,
            market.totalPool,
            market.resolved,
            market.winningOptionId,
            market.cancelled
        );
    }

    function getOptionPool(uint256 _marketId, uint256 _optionId) external view returns (uint256) {
        return markets[_marketId].optionPools[_optionId];
    }
}
