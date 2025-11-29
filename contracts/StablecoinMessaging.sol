// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title StablecoinMessaging
 * @dev Multi-currency messaging supporting cUSD, cEUR, and cREAL stablecoins
 * @author Swift v2 Team
 */
contract StablecoinMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum Currency { cUSD, cEUR, cREAL }

    // Events
    event StablecoinMessageSent(
        uint256 indexed messageId,
        address indexed sender,
        address[] recipients,
        Currency currency,
        uint256 totalAmount,
        uint256 timestamp
    );

    // Structs
    struct StablecoinMessage {
        uint256 id;
        address sender;
        address[] recipients;
        string content;
        Currency currency;
        uint256 amountPerRecipient;
        uint256 timestamp;
        string messageType;
    }

    // State variables
    Counters.Counter private _messageIdCounter;
    mapping(uint256 => StablecoinMessage) public stablecoinMessages;
    mapping(address => uint256[]) public userMessages;

    // Celo stablecoin addresses (Mainnet)
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address public constant CEUR_ADDRESS = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
    address public constant CREAL_ADDRESS = 0xe8537a3d056DA446677B9E9d6c5dB704EaAb4787;

    // Constants
    uint256 public constant MAX_RECIPIENTS = 500;
    uint256 public constant MAX_MESSAGE_LENGTH = 2000;
    uint256 public constant MIN_AMOUNT = 100; // 0.0001 in 18 decimals (very low for Celo)

    constructor() {
        _messageIdCounter.increment();
    }

    /**
     * @dev Get stablecoin address for currency
     */
    function getStablecoinAddress(Currency _currency) public pure returns (address) {
        if (_currency == Currency.cUSD) return CUSD_ADDRESS;
        if (_currency == Currency.cEUR) return CEUR_ADDRESS;
        if (_currency == Currency.cREAL) return CREAL_ADDRESS;
        return CUSD_ADDRESS;
    }

    /**
     * @dev Send message with stablecoin payment
     * @param _recipients Array of recipient addresses
     * @param _content Message content
     * @param _currency Currency to use (cUSD, cEUR, cREAL)
     * @param _amountPerRecipient Amount to send to each recipient
     * @param _messageType Type of message
     */
    function sendStablecoinMessage(
        address[] memory _recipients,
        string memory _content,
        Currency _currency,
        uint256 _amountPerRecipient,
        string memory _messageType
    ) 
        external 
        nonReentrant 
    {
        require(_recipients.length > 0, "No recipients");
        require(_recipients.length <= MAX_RECIPIENTS, "Too many recipients");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        require(_amountPerRecipient >= MIN_AMOUNT, "Amount too small");
        
        address stablecoinAddress = getStablecoinAddress(_currency);
        IERC20 stablecoin = IERC20(stablecoinAddress);
        
        uint256 messageId = _messageIdCounter.current();
        _messageIdCounter.increment();

        StablecoinMessage storage message = stablecoinMessages[messageId];
        message.id = messageId;
        message.sender = msg.sender;
        message.content = _content;
        message.currency = _currency;
        message.amountPerRecipient = _amountPerRecipient;
        message.timestamp = block.timestamp;
        message.messageType = _messageType;

        uint256 validCount = 0;
        for (uint256 i = 0; i < _recipients.length; i++) {
            if (_recipients[i] != address(0) && _recipients[i] != msg.sender) {
                message.recipients.push(_recipients[i]);
                validCount++;
            }
        }

        require(validCount > 0, "No valid recipients");

        uint256 totalAmount = _amountPerRecipient * validCount;
        
        // Transfer stablecoins from sender to contract
        require(
            stablecoin.transferFrom(msg.sender, address(this), totalAmount),
            "Stablecoin transfer failed"
        );

        // Distribute to recipients
        for (uint256 i = 0; i < message.recipients.length; i++) {
            require(
                stablecoin.transfer(message.recipients[i], _amountPerRecipient),
                "Recipient transfer failed"
            );
        }

        userMessages[msg.sender].push(messageId);

        emit StablecoinMessageSent(
            messageId,
            msg.sender,
            message.recipients,
            _currency,
            totalAmount,
            block.timestamp
        );
    }

    /**
     * @dev Get stablecoin message details
     */
    function getStablecoinMessage(uint256 _messageId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address[] memory recipients,
            string memory content,
            Currency currency,
            uint256 amountPerRecipient,
            uint256 timestamp,
            string memory messageType
        )
    {
        StablecoinMessage storage message = stablecoinMessages[_messageId];
        return (
            message.id,
            message.sender,
            message.recipients,
            message.content,
            message.currency,
            message.amountPerRecipient,
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
     * @dev Emergency withdraw (only owner)
     */
    function emergencyWithdraw(address _token) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");

        require(token.transfer(owner(), balance), "Withdraw failed");
    }
}
