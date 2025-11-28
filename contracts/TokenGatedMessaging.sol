// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenGatedMessaging
 * @dev A contract requiring specific token ownership to send or receive messages
 * @author Swift v2 Team
 */
contract TokenGatedMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event TokenGateCreated(
        uint256 indexed gateId,
        address indexed tokenAddress,
        uint256 minBalance,
        uint256 timestamp
    );

    event GatedMessageSent(
        uint256 indexed messageId,
        uint256 indexed gateId,
        address indexed sender,
        address[] recipients,
        uint256 timestamp
    );

    // Structs
    struct TokenGate {
        uint256 id;
        address tokenAddress;
        uint256 minBalance;
        address creator;
        bool isActive;
    }

    struct GatedMessage {
        uint256 id;
        uint256 gateId;
        address sender;
        address[] recipients;
        string content;
        uint256 timestamp;
        string messageType;
    }

    // State variables
    Counters.Counter private _gateIdCounter;
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => TokenGate) public tokenGates;
    mapping(uint256 => GatedMessage) public gatedMessages;
    mapping(address => uint256[]) public userMessages;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant GATED_MESSAGE_FEE = 0.000006 ether;

    // Modifiers
    modifier hasTokenAccess(uint256 _gateId) {
        TokenGate storage gate = tokenGates[_gateId];
        require(gate.isActive, "Gate is not active");
        IERC20 token = IERC20(gate.tokenAddress);
        require(token.balanceOf(msg.sender) >= gate.minBalance, "Insufficient token balance");
        _;
    }

    modifier gateExists(uint256 _gateId) {
        require(_gateId > 0 && _gateId <= _gateIdCounter.current(), "Gate does not exist");
        _;
    }

    constructor() {
        _gateIdCounter.increment();
        _messageIdCounter.increment();
    }

    /**
     * @dev Create a new token gate
     * @param _tokenAddress Address of the ERC20 token
     * @param _minBalance Minimum token balance required
     */
    function createTokenGate(
        address _tokenAddress,
        uint256 _minBalance
    ) 
        external 
        nonReentrant 
    {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_minBalance > 0, "Min balance must be greater than 0");
        
        uint256 gateId = _gateIdCounter.current();
        _gateIdCounter.increment();

        TokenGate storage gate = tokenGates[gateId];
        gate.id = gateId;
        gate.tokenAddress = _tokenAddress;
        gate.minBalance = _minBalance;
        gate.creator = msg.sender;
        gate.isActive = true;

        emit TokenGateCreated(gateId, _tokenAddress, _minBalance, block.timestamp);
    }

    /**
     * @dev Send a token-gated message
     * @param _gateId ID of the token gate
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _messageType Type of message
     */
    function sendGatedMessage(
        uint256 _gateId,
        address[] memory _recipients,
        string memory _content,
        string memory _messageType
    ) 
        external 
        payable 
        nonReentrant 
        gateExists(_gateId)
        hasTokenAccess(_gateId)
    {
        require(msg.value >= GATED_MESSAGE_FEE, "Insufficient fee");
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");

        // Verify all recipients have token access
        TokenGate storage gate = tokenGates[_gateId];
        IERC20 token = IERC20(gate.tokenAddress);
        
        for (uint256 i = 0; i < _recipients.length; i++) {
            require(
                token.balanceOf(_recipients[i]) >= gate.minBalance,
                "Recipient does not have required token balance"
            );
        }
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        GatedMessage storage message = gatedMessages[messageId];
        message.id = messageId;
        message.gateId = _gateId;
        message.sender = msg.sender;
        message.content = _content;
        message.timestamp = block.timestamp;
        message.messageType = _messageType;

        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
            }
        }

        require(message.recipients.length > 0, "No valid recipients");

        userMessages[msg.sender].push(messageId);

        emit GatedMessageSent(
            messageId,
            _gateId,
            msg.sender,
            message.recipients,
            block.timestamp
        );
    }

    /**
     * @dev Toggle gate active status
     * @param _gateId ID of the gate
     */
    function toggleGateStatus(uint256 _gateId) 
        external 
        gateExists(_gateId)
    {
        TokenGate storage gate = tokenGates[_gateId];
        require(gate.creator == msg.sender || msg.sender == owner(), "Not authorized");
        
        gate.isActive = !gate.isActive;
    }

    /**
     * @dev Get token gate details
     */
    function getTokenGate(uint256 _gateId) 
        external 
        view 
        gateExists(_gateId)
        returns (
            uint256 id,
            address tokenAddress,
            uint256 minBalance,
            address creator,
            bool isActive
        )
    {
        TokenGate storage gate = tokenGates[_gateId];
        return (
            gate.id,
            gate.tokenAddress,
            gate.minBalance,
            gate.creator,
            gate.isActive
        );
    }

    /**
     * @dev Get gated message details
     */
    function getGatedMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            uint256 gateId,
            address sender,
            address[] memory recipients,
            string memory content,
            uint256 timestamp,
            string memory messageType
        )
    {
        GatedMessage storage message = gatedMessages[_messageId];
        return (
            message.id,
            message.gateId,
            message.sender,
            message.recipients,
            message.content,
            message.timestamp,
            message.messageType
        );
    }

    /**
     * @dev Get user's messages
     */
    function getUserMessages(address _user) external view returns (uint256[] memory) {
        return userMessages[_user];
    }

    /**
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdraw failed");
    }
}
