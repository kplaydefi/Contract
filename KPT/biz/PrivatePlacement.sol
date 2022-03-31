pragma solidity >=0.5.0 <0.7.0;


import "../../library/SafeMath.sol";
import "../../access/WhitelistedRole.sol";
import "../../common/Pausable.sol";
import "../common/MixinResolver.sol";


contract PrivatePlacement is WhitelistedRole, Pausable, MixinResolver {
    using SafeMath for uint256;

    mapping(uint256 => Order) private _orders;
    mapping(address => uint256) public _buyers;
    uint256 private _counter = 2;
    uint256 public totalSellableDeposits;
    uint256 public totalFunds;
    mapping(address => uint256) public totalDepositedBalance;
    mapping(address => uint256) public totalPurchasedBalance;

    struct Order {
        address seller;
        address buyer;
        uint256 lot;
        uint256 fund;
        uint256 pay;
    }

    constructor() public {
        addWhitelisted(msg.sender);
    }
    
    function counter() public view returns (uint256) {
        return _counter.sub(1);
    }

    function getOrder(address account) public view returns (uint256, address, uint256, uint256, uint256) {
        uint256 id = _buyers[account];
        Order memory order = _orders[id];
        return (id, order.buyer, order.lot, order.fund, order.pay);
    }

    function getOrderById(uint256 id) public view returns (uint256, address, uint256, uint256, uint256) {
        Order memory order = _orders[id];
        return (id, order.buyer, order.lot, order.fund, order.pay);
    }

    function entrust(address seller, address buyer, uint256 lot, uint256 fund, uint256 pay) public onlyWhitelisted returns (uint256) {
        require(_buyers[buyer] < 3, "PrivatePlacement: account's order exist");
        require(seller != address(0), "PrivatePlacement: seller is the zero address");
        require(buyer != address(0), "PrivatePlacement: buyer is the zero address");
        require(lot > 0, "PrivatePlacement: lot is the zero value");
        require(pay > 0, "PrivatePlacement: pay is the zero value");
        require(lot > fund, "PrivatePlacement: lot is smaller than fund");

        require(_counter < uint256(- 1), "PrivatePlacement: counter overflow");
        _counter = _counter.add(1);
        uint256 id = _counter;

        Order memory order = Order(seller, buyer, lot, fund, pay);
        _orders[id] = order;
        totalSellableDeposits = totalSellableDeposits.add(lot);
        totalDepositedBalance[seller] = totalDepositedBalance[seller].add(lot);
        _buyers[buyer] = id;

        kpToken().unpausedTransferFrom(seller, address(this), lot);

        emit Queued(id, seller, buyer, lot, fund, pay);

        return id;
    }

    function cancel(address account) public onlyWhitelisted {
        require(_buyers[account] > 2, "PrivatePlacement: account's order not exist");
        uint256 id = _buyers[account];

        kpToken().unpausedTransfer(_orders[id].seller, _orders[id].lot);

        totalSellableDeposits = totalSellableDeposits.sub(_orders[id].lot);
        totalDepositedBalance[_orders[id].seller] = totalDepositedBalance[_orders[id].seller].sub(_orders[id].lot);
        
        Order memory order = _orders[id];

        delete _orders[id];

        _buyers[account] = 2;

        emit Cancel(id, order.seller, order.buyer, order.lot, order.fund, order.pay);
    }

    function sold() public whenNotPaused {
        require(_buyers[msg.sender] > 2, "PrivatePlacement: not allowed to buy");
        uint256 id = _buyers[msg.sender];
        require(_orders[id].buyer == msg.sender, "PrivatePlacement: caller is not the order‘s buyer");
        require(_orders[id].lot > 0, "PrivatePlacement: lot is the zero value");

        require(usdt().allowance(msg.sender, address(this)) >= _orders[id].pay, "PrivatePlacement: allowance not enough");

        require(usdt().balanceOf(msg.sender) >= _orders[id].pay, "PrivatePlacement: balance not enough");

        usdt().transferFrom(msg.sender, _orders[id].seller, _orders[id].pay);

        kpToken().unpausedTransfer(msg.sender, _orders[id].lot.sub(_orders[id].fund));

        totalSellableDeposits = totalSellableDeposits.sub(_orders[id].lot);
        totalFunds = totalFunds.add(_orders[id].fund);
        totalDepositedBalance[_orders[id].seller] = totalDepositedBalance[_orders[id].seller].sub(_orders[id].lot);
        totalPurchasedBalance[_orders[id].buyer] = totalPurchasedBalance[_orders[id].buyer].add(_orders[id].lot.sub(_orders[id].fund));
        
        Order memory order = _orders[id];

        delete _orders[id];

        _buyers[msg.sender] = 1;

        emit Filled(id, order.seller, order.buyer, order.lot, order.fund, order.pay);
    }

    function withdrawFund(address account, uint256 amount) public onlyWhitelisted {
        require(amount <= totalFunds, "PrivatePlacement: totalFunds is smaller than amount");
        require(account != address(0), "PrivatePlacement: account is the zero address");

        kpToken().transfer(account, amount);
        totalFunds = totalFunds.sub(amount);

        emit WithdrawFund(account, amount);
    }

    event Queued(uint256 indexed id, address indexed seller, address indexed buyer, uint256 lot, uint256 fund, uint256 pay);
    event Filled(uint256 indexed id, address indexed seller, address indexed buyer, uint256 lot, uint256 fund, uint256 pay);
    event Cancel(uint256 indexed id, address indexed seller, address indexed buyer, uint256 lot, uint256 fund, uint256 pay);
    event WithdrawFund(address indexed account, uint256 indexed amount);

}
