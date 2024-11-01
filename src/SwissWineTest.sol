// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SwissWineTest is ERC20, Ownable {
    // ======== State Variables ========
    uint256 private _maxWalletSize; // % of total supply
    bool private _isMaxWalletActive = true;
    mapping(address => bool) private _isExcludedFromMaxWallet;

    uint256 public sellTaxRate;
    mapping(address => bool) private _isExcludedFromTax;

    address[] public contributors;
    mapping(address => uint256) public contributorsToEntitlement;
    uint256 public totalEntitlement;

    // New state variable to control tax
    bool private _isTaxActive = false;

    // ======== Events ========
    event TaxStatusChanged(bool isActive);

    // ======== Constructor ========
    constructor() ERC20("SwissWineTest", "SWEAT") Ownable(msg.sender) {
        _mint(msg.sender, 1_000_000_000 * 10 ** decimals());
        sellTaxRate = 1;
        _maxWalletSize = (totalSupply() * 2) / 100; // 2%
        _isExcludedFromMaxWallet[msg.sender] = true;
        _isExcludedFromTax[msg.sender] = true;
    }

    // ======== Tax Control Functions ========
    /**
     * @dev Activates the tax mechanism.
     */
    function activateTax() external onlyOwner {
        _isTaxActive = true;
        emit TaxStatusChanged(true);
    }

    /**
     * @dev Deactivates the tax mechanism.
     */
    function deactivateTax() external onlyOwner {
        _isTaxActive = false;
        emit TaxStatusChanged(false);
    }

    /**
     * @dev Returns the current status of the tax.
     */
    function isTaxActive() external view returns (bool) {
        return _isTaxActive;
    }

    // ======== Overridden Transfer Functions ========
    /**
     * @dev Overrides the ERC20 transfer function to include max wallet size and sell tax.
     */
    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _checkWalletSize(_msgSender(), to, amount);
        (uint256 transferAmount, uint256 taxAmount) = _calculateTax(
            _msgSender(),
            to,
            amount
        );

        if (taxAmount > 0) {
            super._transfer(_msgSender(), address(this), taxAmount); // Collect tax
        }

        bool success = super.transfer(to, transferAmount);

        if (taxAmount > 0) {
            _distributeTax(taxAmount);
        }

        return success;
    }

    /**
     * @dev Overrides the ERC20 transferFrom function to include max wallet size and sell tax.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _checkWalletSize(from, to, amount);
        (uint256 transferAmount, uint256 taxAmount) = _calculateTax(
            from,
            to,
            amount
        );

        if (taxAmount > 0) {
            super._transfer(from, address(this), taxAmount); // Collect tax
        }

        bool success = super.transferFrom(from, to, transferAmount);

        if (taxAmount > 0) {
            _distributeTax(taxAmount);
        }

        return success;
    }

    // ======== Internal Functions ========
    /**
     * @dev Calculates the tax based on the current tax rate and the tax's active status.
     * @param from The address initiating the transfer.
     * @param to The recipient address.
     * @param amount The amount being transferred.
     * @return transferAmount The amount after tax deduction.
     * @return taxAmount The calculated tax amount.
     */
    function _calculateTax(
        address from,
        address to,
        uint256 amount
    ) internal view returns (uint256 transferAmount, uint256 taxAmount) {
        if (_isTaxActive && !_isExcludedFromTax[from] && !_isExcludedFromTax[to]) {
            taxAmount = (amount * sellTaxRate) / 100;
            transferAmount = amount - taxAmount;
        } else {
            transferAmount = amount;
            taxAmount = 0;
        }
    }

    /**
     * @dev Checks max wallet size constraints.
     */
    function _checkWalletSize(
        address from,
        address to,
        uint256 amount
    ) internal view {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");

        if (
            _isMaxWalletActive &&
            !_isExcludedFromMaxWallet[to] &&
            !_isExcludedFromMaxWallet[from]
        ) {
            require(
                balanceOf(to) + amount <= _maxWalletSize,
                "Transfer exceeds the max wallet size"
            );
        }
    }

    /**
     * @dev Automatically distribute collected tax tokens to contributors.
     */
    function _distributeTax(uint256 taxAmount) internal {
        uint256 totalTaxTokens = taxAmount;
        if (totalTaxTokens == 0 || totalEntitlement == 0) {
            return;
        }

        uint256 length = contributors.length;

        for (uint256 i = 0; i < length; i++) {
            address contributor = contributors[i];
            uint256 entitlement = contributorsToEntitlement[contributor];
            if (entitlement > 0) {
                uint256 share = (totalTaxTokens * entitlement) / totalEntitlement;
                if (share > 0) {
                    super._transfer(address(this), contributor, share);
                }
            }
        }
    }

    // ======== Administrative Functions ========
    /**
     * @dev Functions to deactivate/reactivate the max wallet size limit.
     */
    function deactivateMaxWalletLimit() external onlyOwner {
        _isMaxWalletActive = false;
    }

    function activateMaxWalletLimit() external onlyOwner {
        _isMaxWalletActive = true;
    }

    function isMaxWalletLimitActive() external view returns (bool) {
        return _isMaxWalletActive;
    }

    /**
     * @dev Functions to exclude/include accounts from max wallet size.
     */
    function excludeFromMaxWallet(address account) external onlyOwner {
        _isExcludedFromMaxWallet[account] = true;
    }

    function includeInMaxWallet(address account) external onlyOwner {
        _isExcludedFromMaxWallet[account] = false;
    }

    function isExcludedFromMaxWallet(
        address account
    ) external view returns (bool) {
        return _isExcludedFromMaxWallet[account];
    }

    /**
     * @dev Functions to exclude/include accounts from tax.
     */
    function excludeFromTax(address account) external onlyOwner {
        _isExcludedFromTax[account] = true;
    }

    function includeInTax(address account) external onlyOwner {
        _isExcludedFromTax[account] = false;
    }

    function isExcludedFromTax(address account) external view returns (bool) {
        return _isExcludedFromTax[account];
    }

    /**
     * @dev Sets entitlement for a contributor.
     */
    function setEntitlement(
        address _contributor,
        uint256 _amount
    ) public onlyOwner {
        if (contributorsToEntitlement[_contributor] == 0 && _amount > 0) {
            contributors.push(_contributor);
        } else if (
            _amount == 0 && contributorsToEntitlement[_contributor] > 0
        ) {
            // Remove contributor if entitlement set to zero
            _removeContributor(_contributor);
        }

        totalEntitlement =
            totalEntitlement -
            contributorsToEntitlement[_contributor] +
            _amount;
        contributorsToEntitlement[_contributor] = _amount;
    }

    /**
     * @dev Internal function to remove a contributor.
     */
    function _removeContributor(address _contributor) internal {
        require(
            contributorsToEntitlement[_contributor] > 0,
            "Contributor not found"
        );

        // Remove contributor from the array
        uint256 length = contributors.length;
        for (uint256 i = 0; i < length; i++) {
            if (contributors[i] == _contributor) {
                contributors[i] = contributors[length - 1];
                contributors.pop();
                break;
            }
        }
    }

    /**
     * @dev Updates the sell tax rate.
     */
    function updateTaxRate(uint256 _amount) public onlyOwner {
        require(_amount < 20, "Invalid amount"); // Max 19%
        sellTaxRate = _amount;
    }
}
