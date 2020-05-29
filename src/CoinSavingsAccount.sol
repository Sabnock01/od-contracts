/// CoinSavingsAccount.sol

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.5.15;

import "./Logging.sol";

/*
   "Savings Coin" is obtained when the core coin created by the protocol
   is deposited into this contract. Each "Savings Coin" accrues interest
   at the "Savings Rate". This contract does not implement a user tradeable token
   and is intended to be used with adapters.
         --- `save` your `coin` in the `savings account` ---
   - `savingsRate`: the Savings Rate
   - `savings`: user balance of Savings Coins
   - `deposit`: start saving some coins
   - `withdraw`: withdraw coins from the savings account
   - `updateAccumulatedRate`: perform rate collection
*/

contract CDPEngineLike {
    function transferInternalCoins(address,address,uint256) external;
    function createUnbackedDebt(address,address,uint256) external;
}

contract CoinSavingsAccount is Logging {
    // --- Auth ---
    mapping (address => uint) public authorizedAccounts;
    /**
     * @notice Add auth to an account
     * @param account Account to add auth to
     */
    function addAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 1; }
    /**
     * @notice Remove auth from an account
     * @param account Account to remove auth from
     */
    function removeAuthorization(address account) external emitLog isAuthorized { authorizedAccounts[account] = 0; }
    /**
    * @notice Checks whether msg.sender can call an authed function
    **/
    modifier isAuthorized {
        require(authorizedAccounts[msg.sender] == 1, "CoinSavingsAccount/account-not-authorized");
        _;
    }

    // --- Events ---
    event UpdateAccumulatedRate(uint newAccumulatedRate, uint coinAmount);

    // --- Data ---
    // Amount of coins each user has deposited
    mapping (address => uint256) public savings;

    // Total amount of coins deposited
    uint256 public totalSavings;
    // Per second savings rate
    uint256 public savingsRate;
    // An index representing total accumulated rates
    uint256 public accumulatedRates;

    // CDP database
    CDPEngineLike public cdpEngine;
    // Accounting engine
    address public accountingEngine;
    // When accumulated rates were last updated
    uint256 public latestUpdateTime;
    // Whether this contract is enabled or not
    uint256 public contractEnabled;

    // --- Init ---
    constructor(address cdpEngine_) public {
        authorizedAccounts[msg.sender] = 1;
        cdpEngine = CDPEngineLike(cdpEngine_);
        savingsRate = RAY;
        accumulatedRates = RAY;
        latestUpdateTime = now;
        contractEnabled = 1;
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Administration ---
    /**
     * @notice Modify savings rate
     * @param parameter The name of the parameter modified
     * @param data New value for the parameter
     */
    function modifyParameters(bytes32 parameter, uint256 data) external emitLog isAuthorized {
        require(contractEnabled == 1, "CoinSavingsAccount/contract-not-enabled");
        require(now == latestUpdateTime, "CoinSavingsAccount/accumulation-time-not-updated");
        if (parameter == "savingsRate") savingsRate = data;
        else revert("CoinSavingsAccount/modify-unrecognized-param");
    }
    /**
     * @notice Modify address of the accounting engine
     * @param parameter The name of the parameter modified
     * @param addr New value for the parameter
     */
    function modifyParameters(bytes32 parameter, address addr) external emitLog isAuthorized {
        if (parameter == "accountingEngine") accountingEngine = addr;
        else revert("CoinSavingsAccount/modify-unrecognized-param");
    }
    /**
     * @notice Disable this contract (usually called by Global Settlement)
     */
    function disableContract() external emitLog isAuthorized {
        contractEnabled = 0;
        savingsRate = RAY;
    }

    // --- Savings Rate Accumulation ---
    /**
     * @notice Update the accumulated rates index
     * @dev We return early if 'latestUpdateTime' is smaller or equal to block.timestamp. When the savings
            rate is positive, we create unbacked debt for the accounting engine and issue new coins for
            this contract
     */
    function updateAccumulatedRate() external emitLog returns (uint newAccumulatedRate) {
        if (now <= latestUpdateTime) return accumulatedRates;
        newAccumulatedRate = rmul(rpow(savingsRate, sub(now, latestUpdateTime), RAY), accumulatedRates);
        uint accumulatedRates_ = sub(newAccumulatedRate, accumulatedRates);
        accumulatedRates = newAccumulatedRate;
        latestUpdateTime = now;
        cdpEngine.createUnbackedDebt(address(accountingEngine), address(this), mul(totalSavings, accumulatedRates_));
        emit UpdateAccumulatedRate(newAccumulatedRate, mul(totalSavings, accumulatedRates_));
    }
    /**
     * @notice Get the next value of 'accumulatedRates' without actually updating the variable
     */
    function nextAccumulatedRate() external view returns (uint) {
        if (now <= latestUpdateTime) return accumulatedRates;
        return rmul(rpow(savingsRate, sub(now, latestUpdateTime), RAY), accumulatedRates);
    }

    // --- Savings Management ---
    /**
     * @notice Deposit coins in the savings account
     * @param wad Amount of coins to deposit (expressed as an 18 decimal number). 'wad' will be multiplied by
              'accumulatedRates' (27 decimals) to result in a correct amount of internal coins transferred
     */
    function deposit(uint wad) external emitLog {
        require(now == latestUpdateTime, "CoinSavingsAccount/accumulation-time-not-updated");
        savings[msg.sender] = add(savings[msg.sender], wad);
        totalSavings        = add(totalSavings, wad);
        cdpEngine.transferInternalCoins(msg.sender, address(this), mul(accumulatedRates, wad));
    }
    /**
     * @notice Withdraw coins (alongside any interest accrued) from the savings account
     * @param wad Amount of coins to withdraw (expressed as an 18 decimal number). 'wad' will be multiplied by
              'accumulatedRates' (27 decimals) to result in a correct amount of internal coins transferred
     */
    function withdraw(uint wad) external emitLog {
        savings[msg.sender] = sub(savings[msg.sender], wad);
        totalSavings        = sub(totalSavings, wad);
        cdpEngine.transferInternalCoins(address(this), msg.sender, mul(accumulatedRates, wad));
    }
}