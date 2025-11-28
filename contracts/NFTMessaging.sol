// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title NFTMessaging
 * @dev A contract where each message is minted as an NFT
 * @author Swift v2 Team
 */
contract NFTMessaging is ERC721, ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event MessageNFTMinted(
        uint256 indexed tokenId,
        address indexed sender,
        address indexed recipient,
        string content,
        uint256 timestamp
    );

    // Structs
    struct MessageNFT {
        uint256 tokenId;
        address originalSender;
        address currentRecipient;
        string content;
        uint256 timestamp;
        string messageType;
    }

    // State variables
    Counters.Counter private _tokenIdCounter;
    mapping(uint256 => MessageNFT) public messageNFTs;
    mapping(address => uint256[]) public userSentNFTs;
    mapping(address => uint256[]) public userReceivedNFTs;

    // Constants
    uint256 public constant MINT_FEE = 0.00001 ether;
    uint256 public constant MAX_MESSAGE_LENGTH = 1000;

    constructor() ERC721("MessageNFT", "MNFT") {
        _tokenIdCounter.increment(); // Start from token ID 1
    }

    /**
     * @dev Mint a message as an NFT
     * @param _recipient Address of the recipient
     * @param _content Message content
     * @param _messageType Type of message
     */
    function mintMessageNFT(
        address _recipient,
        string memory _content,
        string memory _messageType
    ) 
        external 
        payable 
        nonReentrant 
    {
        require(msg.value >= MINT_FEE, "Insufficient mint fee");
        require(_recipient != address(0), "Invalid recipient");
        require(_recipient != msg.sender, "Cannot send to yourself");
        require(bytes(_content).length > 0, "Empty content");
        require(bytes(_content).length <= MAX_MESSAGE_LENGTH, "Content too long");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        _safeMint(_recipient, tokenId);

        MessageNFT storage messageNFT = messageNFTs[tokenId];
        messageNFT.tokenId = tokenId;
        messageNFT.originalSender = msg.sender;
        messageNFT.currentRecipient = _recipient;
        messageNFT.content = _content;
        messageNFT.timestamp = block.timestamp;
        messageNFT.messageType = _messageType;

        userSentNFTs[msg.sender].push(tokenId);
        userReceivedNFTs[_recipient].push(tokenId);

        emit MessageNFTMinted(
            tokenId,
            msg.sender,
            _recipient,
            _content,
            block.timestamp
        );
    }

    /**
     * @dev Override transfer to update recipient tracking
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        
        if (to != address(0) && from != address(0)) {
            messageNFTs[tokenId].currentRecipient = to;
        }
    }

    /**
     * @dev Get message NFT details
     */
    function getMessageNFT(uint256 _tokenId) 
        external 
        view 
        returns (
            uint256 tokenId,
            address originalSender,
            address currentRecipient,
            string memory content,
            uint256 timestamp,
            string memory messageType
        )
    {
        require(_exists(_tokenId), "Token does not exist");
        MessageNFT storage messageNFT = messageNFTs[_tokenId];
        
        return (
            messageNFT.tokenId,
            messageNFT.originalSender,
            messageNFT.currentRecipient,
            messageNFT.content,
            messageNFT.timestamp,
            messageNFT.messageType
        );
    }

    /**
     * @dev Get user's sent NFTs
     */
    function getUserSentNFTs(address _user) external view returns (uint256[] memory) {
        return userSentNFTs[_user];
    }

    /**
     * @dev Get user's received NFTs
     */
    function getUserReceivedNFTs(address _user) external view returns (uint256[] memory) {
        return userReceivedNFTs[_user];
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
