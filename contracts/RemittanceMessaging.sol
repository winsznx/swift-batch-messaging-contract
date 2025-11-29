// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title RemittanceMessaging
 * @dev Cross-border remittance with attached messages in multiple currencies
 * @author Swift v2 Team
 */
contract RemittanceMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    enum Currency { cUSD, cEUR, cREAL }

    // Events
    event RemittanceSent(
        uint256 indexed remittanceId,
        address indexed sender,
        address indexed recipient,
        Currency currency,
        uint256 amount,
        string message,
        uint256 timestamp
    );

    event RemittanceClaimed(
        uint256 indexed remittanceId,
        address indexed recipient,
        uint256 timestamp
    );

    // Structs
    struct Remittance {
        uint256 id;
        address sender;
        address recipient;
        Currency currency;
        uint256 amount;
        string message;
        string senderName;
        string recipientName;
        uint256 timestamp;
        bool isClaimed;
        uint256 expiryTime;
    }

    // State variables
    Counters.Counter private _remittanceIdCounter;
    mapping(uint256 => Remittance) public remittances;
    mapping(address => uint256[]) public userSentRemittances;
    mapping(address => uint256[]) public userReceivedRemittances;
    mapping(address => uint256) public totalRemittancesSent;
    mapping(address => uint256) public totalRemittancesReceived;

    // Celo stablecoin addresses
    address public constant CUSD_ADDRESS = 0x765DE816845861e75A25fCA122bb6898B8B1282a;
    address public constant CEUR_ADDRESS = 0xD8763CBa276a3738E6DE85b4b3bF5FDed6D6cA73;
    address public constant CREAL_ADDRESS = 0xe8537a3d056DA446677B9E9d6c5dB704EaAb4787;

    // Constants
    uint256 public constant MAX_MESSAGE_LENGTH = 500;
    uint256 public constant MAX_NAME_LENGTH = 100;
    uint256 public constant DEFAULT_EXPIRY = 2592000; // 30 days
    uint256 public constant REMITTANCE_FEE_BPS = 10; // 0.1% fee

    constructor() {
        _remittanceIdCounter.increment();
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
     * @dev Send remittance with message
     * @param _recipient Recipient address
     * @param _currency Currency to use
     * @param _amount Amount to send
     * @param _message Optional message
     * @param _senderName Sender's name
     * @param _recipientName Recipient's name
     */
    function sendRemittance(
        address _recipient,
        Currency _currency,
        uint256 _amount,
        string memory _message,
        string memory _senderName,
        string memory _recipientName
    ) 
        external 
        nonReentrant 
    {
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(_amount > 0, "Amount must be greater than 0");
        require(bytes(_message).length <= MAX_MESSAGE_LENGTH, "Message too long");
        require(bytes(_senderName).length <= MAX_NAME_LENGTH, "Sender name too long");
        require(bytes(_recipientName).length <= MAX_NAME_LENGTH, "Recipient name too long");
        
        address stablecoinAddress = getStablecoinAddress(_currency);
        IERC20 stablecoin = IERC20(stablecoinAddress);
        
        uint256 remittanceId = _remittanceIdCounter.current();
        _remittanceIdCounter.increment();

        // Calculate fee
        uint256 fee = (_amount * REMITTANCE_FEE_BPS) / 10000;
        uint256 totalAmount = _amount + fee;

        Remittance storage remittance = remittances[remittanceId];
        remittance.id = remittanceId;
        remittance.sender = msg.sender;
        remittance.recipient = _recipient;
        remittance.currency = _currency;
        remittance.amount = _amount;
        remittance.message = _message;
        remittance.senderName = _senderName;
        remittance.recipientName = _recipientName;
        remittance.timestamp = block.timestamp;
        remittance.isClaimed = false;
        remittance.expiryTime = block.timestamp + DEFAULT_EXPIRY;

        // Transfer from sender to contract
        require(
            stablecoin.transferFrom(msg.sender, address(this), totalAmount),
            "Transfer failed"
        );

        userSentRemittances[msg.sender].push(remittanceId);
        userReceivedRemittances[_recipient].push(remittanceId);
        totalRemittancesSent[msg.sender] += _amount;

        emit RemittanceSent(
            remittanceId,
            msg.sender,
            _recipient,
            _currency,
            _amount,
            _message,
            block.timestamp
        );
    }

    /**
     * @dev Claim remittance
     * @param _remittanceId ID of the remittance
     */
    function claimRemittance(uint256 _remittanceId) 
        external 
        nonReentrant 
    {
        Remittance storage remittance = remittances[_remittanceId];
        require(remittance.recipient == msg.sender, "Not the recipient");
        require(!remittance.isClaimed, "Already claimed");
        require(block.timestamp < remittance.expiryTime, "Remittance expired");

        remittance.isClaimed = true;
        totalRemittancesReceived[msg.sender] += remittance.amount;

        address stablecoinAddress = getStablecoinAddress(remittance.currency);
        IERC20 stablecoin = IERC20(stablecoinAddress);

        require(
            stablecoin.transfer(msg.sender, remittance.amount),
            "Claim failed"
        );

        emit RemittanceClaimed(_remittanceId, msg.sender, block.timestamp);
    }

    /**
     * @dev Refund expired remittance to sender
     * @param _remittanceId ID of the remittance
     */
    function refundExpiredRemittance(uint256 _remittanceId) 
        external 
        nonReentrant 
    {
        Remittance storage remittance = remittances[_remittanceId];
        require(remittance.sender == msg.sender, "Not the sender");
        require(!remittance.isClaimed, "Already claimed");
        require(block.timestamp >= remittance.expiryTime, "Not expired yet");

        remittance.isClaimed = true; // Mark as claimed to prevent double refund

        address stablecoinAddress = getStablecoinAddress(remittance.currency);
        IERC20 stablecoin = IERC20(stablecoinAddress);

        require(
            stablecoin.transfer(msg.sender, remittance.amount),
            "Refund failed"
        );
    }

    /**
     * @dev Get remittance details
     */
    function getRemittance(uint256 _remittanceId) 
        external 
        view 
        returns (
            uint256 id,
            address sender,
            address recipient,
            Currency currency,
            uint256 amount,
            string memory message,
            string memory senderName,
            string memory recipientName,
            uint256 timestamp,
            bool isClaimed,
            uint256 expiryTime
        )
    {
        Remittance storage remittance = remittances[_remittanceId];
        return (
            remittance.id,
            remittance.sender,
            remittance.recipient,
            remittance.currency,
            remittance.amount,
            remittance.message,
            remittance.senderName,
            remittance.recipientName,
            remittance.timestamp,
            remittance.isClaimed,
            remittance.expiryTime
        );
    }

    /**
     * @dev Get user's sent remittances
     */
    function getUserSentRemittances(address _user) external view returns (uint256[] memory) {
        return userSentRemittances[_user];
    }

    /**
     * @dev Get user's received remittances
     */
    function getUserReceivedRemittances(address _user) external view returns (uint256[] memory) {
        return userReceivedRemittances[_user];
    }

    /**
     * @dev Get user's total remittances sent
     */
    function getUserTotalSent(address _user) external view returns (uint256) {
        return totalRemittancesSent[_user];
    }

    /**
     * @dev Get user's total remittances received
     */
    function getUserTotalReceived(address _user) external view returns (uint256) {
        return totalRemittancesReceived[_user];
    }

    /**
     * @dev Withdraw collected fees (only owner)
     */
    function withdrawFees(address _token) external onlyOwner nonReentrant {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No balance");

        require(token.transfer(owner(), balance), "Withdraw failed");
    }
}
