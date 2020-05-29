pragma solidity ^0.5.15;

import {DSTest}  from "ds-test/test.sol";
import {DSToken} from "ds-token/token.sol";
import "../DebtAuctionHouse.sol";
import "../CDPEngine.sol";

contract Hevm {
    function warp(uint256) public;
}

contract Guy {
    DebtAuctionHouse debtAuctionHouse;
    constructor(DebtAuctionHouse debtAuctionHouse_) public {
        debtAuctionHouse = debtAuctionHouse_;
        CDPEngine(address(debtAuctionHouse.cdpEngine())).approveCDPModification(address(debtAuctionHouse));
        DSToken(address(debtAuctionHouse.protocolToken())).approve(address(debtAuctionHouse));
    }
    function decreaseSoldAmount(uint id, uint amountToBuy, uint bid) public {
        debtAuctionHouse.decreaseSoldAmount(id, amountToBuy, bid);
    }
    function settleAuction(uint id) public {
        debtAuctionHouse.settleAuction(id);
    }
    function try_decreaseSoldAmount(uint id, uint amountToBuy, uint bid)
        public returns (bool ok)
    {
        string memory sig = "decreaseSoldAmount(uint256,uint256,uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id, amountToBuy, bid));
    }
    function try_settleAuction(uint id)
        public returns (bool ok)
    {
        string memory sig = "settleAuction(uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
    function try_restart_auction(uint id)
        public returns (bool ok)
    {
        string memory sig = "restartAuction(uint256)";
        (ok,) = address(debtAuctionHouse).call(abi.encodeWithSignature(sig, id));
    }
}

contract Gal {
    mapping (uint256 => uint256) public activeDebtAuctions;
    uint256 public activeDebtAuctionsAccumulator;
    uint256 public totalOnAuctionDebt;

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function startAuction(DebtAuctionHouse debtAuctionHouse, uint amountToSell, uint initialBid) external returns (uint) {
        totalOnAuctionDebt += initialBid;
        uint id = debtAuctionHouse.startAuction(address(this), amountToSell, initialBid);
        activeDebtAuctionsAccumulator = activeDebtAuctionsAccumulator + id;
        activeDebtAuctions[id] = 1;
        return id;
    }
    function settleDebtAuction(uint id) external {
        require(activeDebtAuctions[id] == 1, "AccountingEngine/debt-auction-not-active");
        activeDebtAuctions[id] = 0;
        activeDebtAuctionsAccumulator = sub(activeDebtAuctionsAccumulator, id);
    }
    function cancelAuctionedDebtWithSurplus(uint rad) external {
        totalOnAuctionDebt = sub(totalOnAuctionDebt, rad);
    }
    function disableContract(DebtAuctionHouse debtAuctionHouse) external {
        debtAuctionHouse.disableContract();
    }
}

contract CDPEnginish is DSToken('') {
    uint constant ONE = 10 ** 27;
    function transferInternalCoins(address src, address dst, uint rad) public {
        super.transferFrom(src, dst, rad);
    }
    function approveCDPModification(address usr) public {
         super.approve(usr);
    }
    function coin(address usr) public view returns (uint) {
         return super.balanceOf(usr);
    }
}

contract DebtAuctionHouseTest is DSTest {
    Hevm hevm;

    DebtAuctionHouse debtAuctionHouse;
    CDPEngine cdpEngine;
    DSToken protocolToken;

    address ali;
    address bob;
    address accountingEngine;

    function cancelAuctionedDebtWithSurplus(uint) public pure { }  // arbitrary callback

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        cdpEngine = new CDPEngine();
        protocolToken = new DSToken('');

        debtAuctionHouse = new DebtAuctionHouse(address(cdpEngine), address(protocolToken));

        ali = address(new Guy(debtAuctionHouse));
        bob = address(new Guy(debtAuctionHouse));
        accountingEngine = address(new Gal());

        debtAuctionHouse.modifyParameters("accountingEngine", address(accountingEngine));
        debtAuctionHouse.addAuthorization(accountingEngine);
        debtAuctionHouse.removeAuthorization(address(this));

        cdpEngine.approveCDPModification(address(debtAuctionHouse));
        cdpEngine.addAuthorization(address(debtAuctionHouse));
        protocolToken.approve(address(debtAuctionHouse));

        cdpEngine.createUnbackedDebt(address(this), address(this), 1000 ether);

        cdpEngine.transferInternalCoins(address(this), ali, 200 ether);
        cdpEngine.transferInternalCoins(address(this), bob, 200 ether);
    }

    function test_startAuction() public {
        assertEq(cdpEngine.coinBalance(accountingEngine), 0);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 5000 ether);
        // marked auction in the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), id);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), id);
        // no value transferred
        assertEq(cdpEngine.coinBalance(accountingEngine), 0);
        assertEq(protocolToken.balanceOf(accountingEngine), 0 ether);
        // auction created with appropriate values
        assertEq(debtAuctionHouse.auctionsStarted(), id);
        (uint256 bid, uint256 amountToSell, address guy, uint48 bidExpiry, uint48 end) = debtAuctionHouse.bids(id);
        assertEq(bid, 5000 ether);
        assertEq(amountToSell, 200 ether);
        assertTrue(guy == accountingEngine);
        assertEq(uint256(bidExpiry), 0);
        assertEq(uint256(end), now + debtAuctionHouse.totalAuctionLength());
    }
    function test_decreaseSoldAmount() public {
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 10 ether);

        Guy(ali).decreaseSoldAmount(id, 100 ether, 10 ether);
        // bid taken from bidder
        assertEq(cdpEngine.coinBalance(ali), 190 ether);
        // accountingEngine receives payment
        assertEq(cdpEngine.coinBalance(accountingEngine),  10 ether);
        assertEq(Gal(accountingEngine).totalOnAuctionDebt(), 0 ether);

        Guy(bob).decreaseSoldAmount(id, 80 ether, 10 ether);
        // bid taken from bidder
        assertEq(cdpEngine.coinBalance(bob), 190 ether);
        // prev bidder refunded
        assertEq(cdpEngine.coinBalance(ali), 200 ether);
        // accountingEngine receives no more
        assertEq(cdpEngine.coinBalance(accountingEngine), 10 ether);

        hevm.warp(now + 5 weeks);
        assertEq(protocolToken.totalSupply(),  0 ether);
        protocolToken.setOwner(address(debtAuctionHouse));
        Guy(bob).settleAuction(id);
        // marked auction in the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), 0);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), 0);
        // tokens minted on demand
        assertEq(protocolToken.totalSupply(), 80 ether);
        // bob gets the winnings
        assertEq(protocolToken.balanceOf(bob), 80 ether);
    }
    function test_dent_totalOnAuctionDebt_less_than_bid() public {
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 10 ether);
        assertEq(cdpEngine.coinBalance(accountingEngine),  0 ether);

        Gal(accountingEngine).cancelAuctionedDebtWithSurplus(1 ether);
        assertEq(Gal(accountingEngine).totalOnAuctionDebt(), 9 ether);

        Guy(ali).decreaseSoldAmount(id, 100 ether, 10 ether);
        // bid taken from bidder
        assertEq(cdpEngine.coinBalance(ali), 190 ether);
        // accountingEngine receives payment
        assertEq(cdpEngine.coinBalance(accountingEngine),   10 ether);
        assertEq(Gal(accountingEngine).totalOnAuctionDebt(), 0 ether);

        Guy(bob).decreaseSoldAmount(id, 80 ether, 10 ether);
        // bid taken from bidder
        assertEq(cdpEngine.coinBalance(bob), 190 ether);
        // prev bidder refunded
        assertEq(cdpEngine.coinBalance(ali), 200 ether);
        // accountingEngine receives no more
        assertEq(cdpEngine.coinBalance(accountingEngine), 10 ether);

        hevm.warp(now + 5 weeks);
        assertEq(protocolToken.totalSupply(),  0 ether);
        protocolToken.setOwner(address(debtAuctionHouse));
        Guy(bob).settleAuction(id);
        // marked auction in the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), 0);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), 0);
        // tokens minted on demand
        assertEq(protocolToken.totalSupply(), 80 ether);
        // bob gets the winnings
        assertEq(protocolToken.balanceOf(bob), 80 ether);
    }
    function test_restart_auction() public {
        // start an auction
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 10 ether);
        // check no restarting
        assertTrue(!Guy(ali).try_restart_auction(id));
        // run past the end
        hevm.warp(now + 2 weeks);
        // check not biddable
        assertTrue(!Guy(ali).try_decreaseSoldAmount(id, 100 ether, 10 ether));
        assertTrue( Guy(ali).try_restart_auction(id));
        // left auction in the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), id);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), id);
        // check biddable
        (, uint _amountToSell,,,) = debtAuctionHouse.bids(id);
        // restart should increase the amountToSell by pad (50%) and restart the auction
        assertEq(_amountToSell, 300 ether);
        assertTrue( Guy(ali).try_decreaseSoldAmount(id, 100 ether, 10 ether));
    }

    function test_no_deal_after_end() public {
        // if there are no bids and the auction ends, then it should not
        // be refundable to the creator. Rather, it restarts indefinitely.
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 10 ether);
        assertTrue(!Guy(ali).try_settleAuction(id));
        hevm.warp(now + 2 weeks);
        assertTrue(!Guy(ali).try_settleAuction(id));
        assertTrue( Guy(ali).try_restart_auction(id));
        // left auction in the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), id);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), id);
        assertTrue(!Guy(ali).try_settleAuction(id));
    }

    function test_terminate_prematurely() public {
        // terminating the auction prematurely should refund the last bidder's coin, credit a
        // corresponding amount of sin to the caller of cage, and delete the auction.
        // in practice, accountingEngine == (caller of cage)
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 10 ether);

        // confrim initial state expectations
        assertEq(cdpEngine.coinBalance(ali), 200 ether);
        assertEq(cdpEngine.coinBalance(bob), 200 ether);
        assertEq(cdpEngine.coinBalance(accountingEngine), 0);
        assertEq(cdpEngine.debtBalance(accountingEngine), 0);

        Guy(ali).decreaseSoldAmount(id, 100 ether, 10 ether);
        Guy(bob).decreaseSoldAmount(id, 80 ether, 10 ether);

        // confirm the proper state updates have occurred
        assertEq(cdpEngine.coinBalance(ali), 200 ether);  // ali's coin balance is unchanged
        assertEq(cdpEngine.coinBalance(bob), 190 ether);
        assertEq(cdpEngine.coinBalance(accountingEngine),  10 ether);
        assertEq(cdpEngine.debtBalance(address(this)), 1000 ether);

        Gal(accountingEngine).disableContract(debtAuctionHouse);
        debtAuctionHouse.terminateAuctionPrematurely(id);

        // deleted auction from the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), 0);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), 0);
        // confirm final state
        assertEq(cdpEngine.coinBalance(ali), 200 ether);
        assertEq(cdpEngine.coinBalance(bob), 200 ether);  // bob's bid has been refunded
        assertEq(cdpEngine.coinBalance(accountingEngine),  10 ether);
        assertEq(cdpEngine.debtBalance(accountingEngine),  10 ether);  // sin assigned to caller of disableContract()
        (uint256 _bid, uint256 _amountToSell, address _guy, uint48 _bidExpiry, uint48 _end) = debtAuctionHouse.bids(id);
        assertEq(_bid, 0);
        assertEq(_amountToSell, 0);
        assertEq(_guy, address(0));
        assertEq(uint256(_bidExpiry), 0);
        assertEq(uint256(_end), 0);
    }

    function test_terminate_prematurely_no_bids() public {
        // with no bidder to refund, terminating the auction prematurely should simply create equal
        // amounts of coin (credited to the accountingEngine) and sin (credited to the caller of cage)
        // in practice, accountingEngine == (caller of cage)
        uint id = Gal(accountingEngine).startAuction(debtAuctionHouse, /*amountToSell*/ 200 ether, /*bid*/ 10 ether);

        // confrim initial state expectations
        assertEq(cdpEngine.coinBalance(ali), 200 ether);
        assertEq(cdpEngine.coinBalance(bob), 200 ether);
        assertEq(cdpEngine.coinBalance(accountingEngine), 0);
        assertEq(cdpEngine.debtBalance(accountingEngine), 0);

        Gal(accountingEngine).disableContract(debtAuctionHouse);
        debtAuctionHouse.terminateAuctionPrematurely(id);

        // deleted auction from the accounting engine
        assertEq(Gal(accountingEngine).activeDebtAuctions(id), 0);
        assertEq(Gal(accountingEngine).activeDebtAuctionsAccumulator(), 0);
        // confirm final state
        assertEq(cdpEngine.coinBalance(ali), 200 ether);
        assertEq(cdpEngine.coinBalance(bob), 200 ether);
        assertEq(cdpEngine.coinBalance(accountingEngine),  10 ether);
        assertEq(cdpEngine.debtBalance(accountingEngine),  10 ether);  // sin assigned to caller of disableContract()
        (uint256 _bid, uint256 _amountToSell, address _guy, uint48 _bidExpiry, uint48 _end) = debtAuctionHouse.bids(id);
        assertEq(_bid, 0);
        assertEq(_amountToSell, 0);
        assertEq(_guy, address(0));
        assertEq(uint256(_bidExpiry), 0);
        assertEq(uint256(_end), 0);
    }
}