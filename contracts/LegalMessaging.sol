// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title LegalMessaging
 * @dev Contract for creating and signing legal agreements via messages
 * @author Swift v2 Team
 */
contract LegalMessaging is ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;

    // Events
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed creator,
        string title,
        uint256 timestamp
    );

    event AgreementSigned(
        uint256 indexed agreementId,
        address indexed signer,
        uint256 timestamp
    );

    event AgreementFinalized(
        uint256 indexed agreementId,
        uint256 timestamp
    );

    event AgreementRevoked(
        uint256 indexed agreementId,
        address indexed revoker,
        string reason
    );

    // Structs
    struct Agreement {
        uint256 id;
        address creator;
        string title;
        string contentHash; // IPFS hash or similar of the full legal text
        address[] requiredSigners;
        mapping(address => bool) hasSigned;
        uint256 signatureCount;
        bool isFinalized;
        bool isRevoked;
        uint256 createdAt;
        uint256 finalizedAt;
    }

    // State variables
    Counters.Counter private _agreementIdCounter;
    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256[]) public userAgreements;

    constructor() {
        _agreementIdCounter.increment();
    }

    /**
     * @dev Create a new legal agreement
     * @param _title Title of the agreement
     * @param _contentHash Hash of the agreement content
     * @param _signers List of addresses required to sign
     */
    function createAgreement(
        string memory _title,
        string memory _contentHash,
        address[] memory _signers
    ) external nonReentrant {
        require(bytes(_title).length > 0, "Title required");
        require(bytes(_contentHash).length > 0, "Content hash required");
        require(_signers.length > 0, "Signers required");

        uint256 agreementId = _agreementIdCounter.current();
        _agreementIdCounter.increment();

        Agreement storage agreement = agreements[agreementId];
        agreement.id = agreementId;
        agreement.creator = msg.sender;
        agreement.title = _title;
        agreement.contentHash = _contentHash;
        agreement.requiredSigners = _signers;
        agreement.createdAt = block.timestamp;

        // Add creator to user lists
        userAgreements[msg.sender].push(agreementId);
        
        // Add signers to user lists
        for (uint256 i = 0; i < _signers.length; i++) {
            if (_signers[i] != msg.sender) {
                userAgreements[_signers[i]].push(agreementId);
            }
        }

        emit AgreementCreated(agreementId, msg.sender, _title, block.timestamp);
    }

    /**
     * @dev Sign an agreement
     * @param _agreementId Agreement ID
     */
    function signAgreement(uint256 _agreementId) external nonReentrant {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.id != 0, "Agreement does not exist");
        require(!agreement.isRevoked, "Agreement revoked");
        require(!agreement.isFinalized, "Agreement already finalized");
        require(!agreement.hasSigned[msg.sender], "Already signed");

        bool isRequired = false;
        for (uint256 i = 0; i < agreement.requiredSigners.length; i++) {
            if (agreement.requiredSigners[i] == msg.sender) {
                isRequired = true;
                break;
            }
        }
        require(isRequired, "Not a required signer");

        agreement.hasSigned[msg.sender] = true;
        agreement.signatureCount++;

        emit AgreementSigned(_agreementId, msg.sender, block.timestamp);

        // Check if all have signed
        if (agreement.signatureCount == agreement.requiredSigners.length) {
            agreement.isFinalized = true;
            agreement.finalizedAt = block.timestamp;
            emit AgreementFinalized(_agreementId, block.timestamp);
        }
    }

    /**
     * @dev Revoke an agreement (only creator before finalization)
     */
    function revokeAgreement(uint256 _agreementId, string memory _reason) external nonReentrant {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.creator == msg.sender, "Only creator can revoke");
        require(!agreement.isFinalized, "Cannot revoke finalized agreement");
        require(!agreement.isRevoked, "Already revoked");

        agreement.isRevoked = true;
        
        emit AgreementRevoked(_agreementId, msg.sender, _reason);
    }

    /**
     * @dev Check if user has signed
     */
    function hasUserSigned(uint256 _agreementId, address _user) external view returns (bool) {
        return agreements[_agreementId].hasSigned[_user];
    }

    /**
     * @dev Get agreement details
     */
    function getAgreement(uint256 _agreementId) external view returns (
        address creator,
        string memory title,
        string memory contentHash,
        address[] memory requiredSigners,
        uint256 signatureCount,
        bool isFinalized,
        bool isRevoked,
        uint256 createdAt
    ) {
        Agreement storage agreement = agreements[_agreementId];
        return (
            agreement.creator,
            agreement.title,
            agreement.contentHash,
            agreement.requiredSigners,
            agreement.signatureCount,
            agreement.isFinalized,
            agreement.isRevoked,
            agreement.createdAt
        );
    }
}
