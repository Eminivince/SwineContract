// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TokenDistributor
 * @dev Distributes a fixed amount of ERC20 tokens to a list of addresses.
 */
interface IERC20 {
    /**
     * @dev Transfers `amount` tokens to `recipient`.
     * Returns a boolean value indicating whether the operation succeeded.
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the token balance of `account`.
     */
    function balanceOf(address account) external view returns (uint256);
}

contract TokenDistributor {
    // State variables
    address public owner;      // Owner of the contract
    IERC20 public token;       // ERC20 token to be distributed

    // Events
    event TokensDistributed(address indexed token, uint256 totalAmount, uint256 recipients);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TokensWithdrawn(address indexed token, uint256 amount, address indexed to);

    /**
     * @dev Modifier to restrict function access to only the owner.
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    /**
     * @dev Sets the deployer as the initial owner and initializes the ERC20 token address.
     * @param _tokenAddress Address of the ERC20 token to be distributed.
     */
    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        owner = msg.sender;
        token = IERC20(_tokenAddress);
    }

    /**
     * @dev Transfers ownership of the contract to a new address.
     * Can only be called by the current owner.
     * @param newOwner Address of the new owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Distributes a fixed amount of ERC20 tokens to each address in the `recipients` array.
     * Can only be called by the contract owner.
     * @param recipients Array of recipient addresses.
     */
    function distributeTokens(address[] calldata recipients) external onlyOwner {
        uint256 amountPerRecipient = 130200 * (10 ** 18); // Adjust based on token decimals (assuming 18)
        uint256 totalAmount = amountPerRecipient * recipients.length;
        uint256 contractBalance = token.balanceOf(address(this));
        
        require(recipients.length > 0, "No recipients provided");
        require(totalAmount > 0, "Total amount must be greater than zero");
        require(contractBalance >= totalAmount, "Insufficient token balance in contract");

        for(uint256 i = 0; i < recipients.length; i++) {
            address recipient = recipients[i];
            require(recipient != address(0), "Cannot transfer to the zero address");
            bool success = token.transfer(recipient, amountPerRecipient);
            require(success, "Token transfer failed");
        }

        emit TokensDistributed(address(token), totalAmount, recipients.length);
    }

    /**
     * @dev Allows the owner to withdraw a specific amount of ERC20 tokens from the contract.
     * Useful for recovering tokens accidentally sent to the contract.
     * Can only be called by the contract owner.
     * @param _token Address of the ERC20 token to withdraw.
     * @param _amount Amount of tokens to withdraw (in smallest unit, e.g., wei).
     * @param _to Address to receive the withdrawn tokens.
     */
    function withdrawTokens(address _token, uint256 _amount, address _to) external onlyOwner {
        require(_token != address(0), "Token address cannot be zero");
        require(_to != address(0), "Recipient address cannot be zero");
        bool success = IERC20(_token).transfer(_to, _amount);
        require(success, "Token withdrawal failed");
        emit TokensWithdrawn(_token, _amount, _to);
    }

    /**
     * @dev Fallback function to prevent accidental Ether transfers to the contract.
     * Reverts any incoming Ether.
     */
    receive() external payable {
        revert("Contract does not accept Ether");
    }
}
