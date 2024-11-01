// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PiggyBank
 * @dev ERC20 token representing expected rewards from fixed staking.
 * Only the owner (SwineStake contract) can mint and burn tokens.
 */
contract PiggyBank is ERC20, Ownable {
    /**
     * @dev Constructor that gives the token a name and a symbol.
     */
    constructor() ERC20("PiggyBank", "PGB") Ownable(msg.sender) {}

    /**
     * @notice Mints PiggyBank tokens to a specified address.
     * @param to The address to mint tokens to.
     * @param amount The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Burns PiggyBank tokens from a specified address.
     * @param from The address to burn tokens from.
     * @param amount The number of tokens to burn.
     */
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }

    /**
     * @dev Overrides the ERC20 transfer function to prevent transfers.
     * This makes PiggyBank tokens non-transferable.
     */
    function transfer(address, uint256) public pure override returns (bool) {
        revert("PiggyBank tokens are non-transferable");
    }

    /**
     * @dev Overrides the ERC20 transferFrom function to prevent transfers.
     * This makes PiggyBank tokens non-transferable.
     */
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert("PiggyBank tokens are non-transferable");
    }
}
