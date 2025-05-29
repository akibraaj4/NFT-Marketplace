// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarketplace is ReentrancyGuard, Ownable {
    
    // Struct to represent a listed NFT
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool active;
    }
    
    // Mapping from listing ID to Listing
    mapping(uint256 => Listing) public listings;
    
    // Counter for listing IDs
    uint256 public listingCounter;
    
    // Platform fee percentage (e.g., 250 = 2.5%)
    uint256 public platformFee = 250; // 2.5%
    uint256 private constant PERCENTAGE_BASE = 10000;
    
    // Events
    event NFTListed(
        uint256 indexed listingId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 price
    );
    
    event NFTSold(
        uint256 indexed listingId,
        address indexed buyer,
        address indexed seller,
        uint256 price
    );
    
    event ListingCancelled(uint256 indexed listingId);
    
    constructor() Ownable(msg.sender) {}
    
    /**
     * @dev Core Function 1: List an NFT for sale
     * @param _nftContract Address of the NFT contract
     * @param _tokenId Token ID of the NFT
     * @param _price Price in wei
     */
    function listNFT(
        address _nftContract,
        uint256 _tokenId,
        uint256 _price
    ) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        require(_nftContract != address(0), "Invalid NFT contract address");
        
        IERC721 nftContract = IERC721(_nftContract);
        require(nftContract.ownerOf(_tokenId) == msg.sender, "You don't own this NFT");
        require(
            nftContract.isApprovedForAll(msg.sender, address(this)) || 
            nftContract.getApproved(_tokenId) == address(this),
            "Marketplace not approved to transfer NFT"
        );
        
        uint256 listingId = listingCounter++;
        
        listings[listingId] = Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            price: _price,
            active: true
        });
        
        emit NFTListed(listingId, msg.sender, _nftContract, _tokenId, _price);
    }
    
    /**
     * @dev Core Function 2: Buy an NFT from the marketplace
     * @param _listingId ID of the listing to purchase
     */
    function buyNFT(uint256 _listingId) external payable nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.active, "Listing is not active");
        require(msg.value >= listing.price, "Insufficient payment");
        require(msg.sender != listing.seller, "Cannot buy your own NFT");
        
        IERC721 nftContract = IERC721(listing.nftContract);
        require(nftContract.ownerOf(listing.tokenId) == listing.seller, "NFT no longer owned by seller");
        
        // Calculate platform fee
        uint256 fee = (listing.price * platformFee) / PERCENTAGE_BASE;
        uint256 sellerProceeds = listing.price - fee;
        
        // Mark listing as inactive
        listing.active = false;
        
        // Transfer NFT to buyer
        nftContract.safeTransferFrom(listing.seller, msg.sender, listing.tokenId);
        
        // Transfer payment to seller
        (bool success, ) = payable(listing.seller).call{value: sellerProceeds}("");
        require(success, "Payment to seller failed");
        
        // Refund excess payment
        if (msg.value > listing.price) {
            (bool refundSuccess, ) = payable(msg.sender).call{value: msg.value - listing.price}("");
            require(refundSuccess, "Refund failed");
        }
        
        emit NFTSold(_listingId, msg.sender, listing.seller, listing.price);
    }
    
    /**
     * @dev Core Function 3: Cancel an NFT listing
     * @param _listingId ID of the listing to cancel
     */
    function cancelListing(uint256 _listingId) external nonReentrant {
        Listing storage listing = listings[_listingId];
        
        require(listing.active, "Listing is not active");
        require(
            msg.sender == listing.seller || msg.sender == owner(),
            "Only seller or owner can cancel listing"
        );
        
        listing.active = false;
        
        emit ListingCancelled(_listingId);
    }
    
    /**
     * @dev Get listing details
     * @param _listingId ID of the listing
     */
    function getListing(uint256 _listingId) external view returns (Listing memory) {
        return listings[_listingId];
    }
    
    /**
     * @dev Update platform fee (only owner)
     * @param _newFee New fee percentage (e.g., 250 = 2.5%)
     */
    function updatePlatformFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= 1000, "Fee cannot exceed 10%");
        platformFee = _newFee;
    }
    
    /**
     * @dev Withdraw platform fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    /**
     * @dev Get total number of listings created
     */
    function getTotalListings() external view returns (uint256) {
        return listingCounter;
    }
}
