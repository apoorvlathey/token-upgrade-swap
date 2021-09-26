pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function _setOwnership() internal virtual {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }
}

interface IDGVC is IERC20 {
    function burn(uint amount) external returns (bool);
}

contract DGVCImplementation is IDGVC, Context, Ownable {
    using SafeERC20 for IERC20;

    mapping (address => uint) private _reflectionOwned;
    mapping (address => uint) private _actualOwned;
    mapping (address => mapping (address => uint)) private _allowances;
    mapping (address => CustomFees) public customFees;
    mapping (address => DexFOT) public dexFOT;

    struct DexFOT {
        bool enabled;
        uint16 buy;
        uint16 sell;
        uint16 burn;
    }

    struct CustomFees {
       bool enabled;
       uint16 fot;
       uint16 burn;
    }


    mapping (address => bool) private _isExcluded;
    address[] private _excluded;
    address public feeReceiver;
    address public router;

    string  private constant _NAME = "Degen.vc";
    string  private constant _SYMBOL = "DGVC";
    uint8   private constant _DECIMALS = 18;

    uint private constant _MAX = type(uint).max;
    uint private constant _DECIMALFACTOR = 10 ** uint(_DECIMALS);
    uint private constant _DIVIDER = 10000;

    uint private _actualTotal;
    uint private _reflectionTotal;

    uint private _actualFeeTotal;
    uint private _actualBurnTotal;

    uint public actualBurnCycle;

    uint public commonBurnFee;
    uint public commonFotFee;

    uint public rebaseDelta;
    uint public burnCycleLimit;

    uint private constant _MAX_TX_SIZE = 12000000 * _DECIMALFACTOR;

    bool public initiated;

    event BurnCycleLimitSet(uint cycleLimit);
    event RebaseDeltaSet(uint delta);
    event Rebase(uint rebased);
    event TokensRecovered(address token, address to, uint value);


    function init(address _router) external returns (bool) {
        require(!initiated, 'Already initiated');
        _actualTotal = 12000000 * _DECIMALFACTOR;
        _reflectionTotal = (_MAX - (_MAX % _actualTotal));
        _setOwnership();
        _reflectionOwned[_msgSender()] = _reflectionTotal;
        router = _router;
        emit Transfer(address(0), _msgSender(), _actualTotal);

        initiated = true;
        return true;
    }

    function name() public pure returns (string memory) {
        return _NAME;
    }

    function symbol() public pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() public pure returns (uint8) {
        return _DECIMALS;
    }

    function totalSupply() public view override returns (uint) {
        return _actualTotal;
    }

    function balanceOf(address account) public view override returns (uint) {
        if (_isExcluded[account]) return _actualOwned[account];
        return tokenFromReflection(_reflectionOwned[account]);
    }

    function transfer(address recipient, uint amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        require(_allowances[sender][_msgSender()] >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    function isExcluded(address account) public view returns (bool) {
        return _isExcluded[account];
    }

    function totalFees() public view returns (uint) {
        return _actualFeeTotal;
    }

    function totalBurn() public view returns (uint) {
        return _actualBurnTotal;
    }

    function setFeeReceiver(address receiver) external onlyOwner returns (bool) {
        require(receiver != address(0), "Zero address not allowed");
        feeReceiver = receiver;
        return true;
    }

    function reflectionFromToken(uint transferAmount, bool deductTransferFee) public view returns(uint) {
        require(transferAmount <= _actualTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint reflectionAmount,,,,,) = _getValues(transferAmount, address(0), address(0));
            return reflectionAmount;
        } else {
            (,uint reflectionTransferAmount,,,,) = _getValues(transferAmount, address(0), address(0));
            return reflectionTransferAmount;
        }
    }

    function tokenFromReflection(uint reflectionAmount) public view returns(uint) {
        require(reflectionAmount <= _reflectionTotal, "Amount must be less than total reflections");
        return reflectionAmount / _getRate();
    }

    function excludeAccount(address account) external onlyOwner {
        require(!_isExcluded[account], "Account is already excluded");
        require(account != router, 'Not allowed to exclude router');
        require(account != feeReceiver, "Can not exclude fee receiver");
        if (_reflectionOwned[account] > 0) {
            _actualOwned[account] = tokenFromReflection(_reflectionOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    function includeAccount(address account) external onlyOwner {
        require(_isExcluded[account], "Account is already included");
        for (uint i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _actualOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    function _approve(address owner, address spender, uint amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address sender, address recipient, uint amount) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (sender != owner() && recipient != owner())
            require(amount <= _MAX_TX_SIZE, "Transfer amount exceeds the maxTxAmount.");

        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    function _transferStandard(address sender, address recipient, uint transferAmount) private {
        uint currentRate =  _getRate();
        (uint reflectionAmount, uint reflectionTransferAmount, uint reflectionFee, uint actualTransferAmount, uint transferFee, uint transferBurn) = _getValues(transferAmount, sender, recipient);
        uint reflectionBurn =  transferBurn * currentRate;
        _reflectionOwned[sender] = _reflectionOwned[sender] - reflectionAmount;
        _reflectionOwned[recipient] = _reflectionOwned[recipient] + reflectionTransferAmount;

        _reflectionOwned[feeReceiver] = _reflectionOwned[feeReceiver] + reflectionFee;

        _burnAndRebase(reflectionBurn, transferFee, transferBurn);
        emit Transfer(sender, recipient, actualTransferAmount);

        if (transferFee > 0) {
            emit Transfer(sender, feeReceiver, transferFee);
        }
    }

    function _transferToExcluded(address sender, address recipient, uint transferAmount) private {
        uint currentRate =  _getRate();
        (uint reflectionAmount, uint reflectionTransferAmount, uint reflectionFee, uint actualTransferAmount, uint transferFee, uint transferBurn) = _getValues(transferAmount, sender, recipient);
        uint reflectionBurn =  transferBurn * currentRate;
        _reflectionOwned[sender] = _reflectionOwned[sender] - reflectionAmount;
        _actualOwned[recipient] = _actualOwned[recipient] + actualTransferAmount;
        _reflectionOwned[recipient] = _reflectionOwned[recipient] + reflectionTransferAmount;

        _reflectionOwned[feeReceiver] = _reflectionOwned[feeReceiver] + reflectionFee;

        _burnAndRebase(reflectionBurn, transferFee, transferBurn);
        emit Transfer(sender, recipient, actualTransferAmount);

        if (transferFee > 0) {
            emit Transfer(sender, feeReceiver, transferFee);
        }
    }

    function _transferFromExcluded(address sender, address recipient, uint transferAmount) private {
        uint currentRate =  _getRate();
        (uint reflectionAmount, uint reflectionTransferAmount, uint reflectionFee, uint actualTransferAmount, uint transferFee, uint transferBurn) = _getValues(transferAmount, sender, recipient);
        uint reflectionBurn =  transferBurn * currentRate;
        _actualOwned[sender] = _actualOwned[sender] - transferAmount;
        _reflectionOwned[sender] = _reflectionOwned[sender] - reflectionAmount;
        _reflectionOwned[recipient] = _reflectionOwned[recipient] + reflectionTransferAmount;

        _reflectionOwned[feeReceiver] = _reflectionOwned[feeReceiver] + reflectionFee;

        _burnAndRebase(reflectionBurn, transferFee, transferBurn);
        emit Transfer(sender, recipient, actualTransferAmount);

        if (transferFee > 0) {
            emit Transfer(sender, feeReceiver, transferFee);
        }
    }

    function _transferBothExcluded(address sender, address recipient, uint transferAmount) private {
        uint currentRate =  _getRate();
        (uint reflectionAmount, uint reflectionTransferAmount, uint reflectionFee, uint actualTransferAmount, uint transferFee, uint transferBurn) = _getValues(transferAmount, sender, recipient);
        uint reflectionBurn =  transferBurn * currentRate;
        _actualOwned[sender] = _actualOwned[sender] - transferAmount;
        _reflectionOwned[sender] = _reflectionOwned[sender] - reflectionAmount;
        _actualOwned[recipient] = _actualOwned[recipient] + actualTransferAmount;
        _reflectionOwned[recipient] = _reflectionOwned[recipient] + reflectionTransferAmount;

        _reflectionOwned[feeReceiver] = _reflectionOwned[feeReceiver] + reflectionFee;

        _burnAndRebase(reflectionBurn, transferFee, transferBurn);
        emit Transfer(sender, recipient, actualTransferAmount);

        if (transferFee > 0) {
            emit Transfer(sender, feeReceiver, transferFee);
        }
    }

    function _burnAndRebase(uint reflectionBurn, uint transferFee, uint transferBurn) private {
        _reflectionTotal = _reflectionTotal - reflectionBurn;
        _actualFeeTotal = _actualFeeTotal + transferFee;
        _actualBurnTotal = _actualBurnTotal + transferBurn;
        actualBurnCycle = actualBurnCycle + transferBurn;
        _actualTotal = _actualTotal - transferBurn;


        if (actualBurnCycle >= burnCycleLimit) {
            actualBurnCycle = actualBurnCycle - burnCycleLimit;
            _rebase();
        }
    }

    function burn(uint amount) external override returns (bool) {
        address sender  = _msgSender();
        uint balance = balanceOf(sender);
        require(balance >= amount, "Cannot burn more than on balance");
        require(sender == feeReceiver, "Only feeReceiver");

        uint reflectionBurn =  amount * _getRate();
        _reflectionTotal = _reflectionTotal - reflectionBurn;
        _reflectionOwned[sender] = _reflectionOwned[sender] - reflectionBurn;

        _actualBurnTotal = _actualBurnTotal + amount;
        _actualTotal = _actualTotal - amount;

        emit Transfer(sender, address(0), amount);
        return true;
    }

    function _commonFotFee(address sender, address recipient) private view returns (uint fotFee, uint burnFee) {
        DexFOT memory dexFotSender = dexFOT[sender];
        DexFOT memory dexFotRecepient = dexFOT[recipient];
        CustomFees memory _customFees = customFees[sender];

        if (dexFotSender.enabled) {
            return (dexFotSender.buy, dexFotSender.burn);
        } else if (dexFotRecepient.enabled) {
            return (dexFotRecepient.sell, dexFotRecepient.burn);
        }
        else if (_customFees.enabled) {
            return (_customFees.fot, _customFees.burn);
        } else {
            return (commonFotFee, commonBurnFee);
        }
    }

    function _getValues(uint transferAmount, address sender, address recipient) private view returns (uint, uint, uint, uint, uint, uint) {
        (uint actualTransferAmount, uint transferFee, uint transferBurn) = _getActualValues(transferAmount, sender, recipient);
        (uint reflectionAmount, uint reflectionTransferAmount, uint reflectionFee) = _getReflectionValues(transferAmount, transferFee, transferBurn);
        return (reflectionAmount, reflectionTransferAmount, reflectionFee, actualTransferAmount, transferFee, transferBurn);
    }

    function _getActualValues(uint transferAmount, address sender, address recipient) private view returns (uint, uint, uint) {
        (uint fotFee, uint burnFee) = _commonFotFee(sender, recipient);
        uint transferFee = transferAmount * fotFee / _DIVIDER;
        uint transferBurn = transferAmount * burnFee / _DIVIDER;
        uint actualTransferAmount = transferAmount - transferFee - transferBurn;
        return (actualTransferAmount, transferFee, transferBurn);
    }

    function _getReflectionValues(uint transferAmount, uint transferFee, uint transferBurn) private view returns (uint, uint, uint) {
        uint currentRate =  _getRate();
        uint reflectionAmount = transferAmount * currentRate;
        uint reflectionFee = transferFee * currentRate;
        uint reflectionBurn = transferBurn * currentRate;
        uint reflectionTransferAmount = reflectionAmount - reflectionFee - reflectionBurn;
        return (reflectionAmount, reflectionTransferAmount, reflectionFee);
    }

    function _getRate() private view returns(uint) {
        (uint reflectionSupply, uint actualSupply) = _getCurrentSupply();
        return reflectionSupply / actualSupply;
    }

    function _getCurrentSupply() private view returns(uint, uint) {
        uint reflectionSupply = _reflectionTotal;
        uint actualSupply = _actualTotal;
        for (uint i = 0; i < _excluded.length; i++) {
            if (_reflectionOwned[_excluded[i]] > reflectionSupply || _actualOwned[_excluded[i]] > actualSupply) return (_reflectionTotal, _actualTotal);
            reflectionSupply = reflectionSupply - _reflectionOwned[_excluded[i]];
            actualSupply = actualSupply - _actualOwned[_excluded[i]];
        }
        if (reflectionSupply < _reflectionTotal / _actualTotal) return (_reflectionTotal, _actualTotal);
        return (reflectionSupply, actualSupply);
    }

    function setUserCustomFee(address account, uint16 fee, uint16 burnFee) external onlyOwner {
        require(fee + burnFee <= _DIVIDER, "Total fee should be in 0 - 100%");
        require(account != address(0), "Zero address not allowed");
        customFees[account] = CustomFees(true, fee, burnFee);
    }

    function setDexFee(address pair, uint16 buyFee, uint16 sellFee, uint16 burnFee) external onlyOwner {
        require(pair != address(0), "Zero address not allowed");
        require(buyFee + burnFee <= _DIVIDER, "Total fee should be in 0 - 100%");
        require(sellFee + burnFee <= _DIVIDER, "Total fee should be in 0 - 100%");
        dexFOT[pair] = DexFOT(true, buyFee, sellFee, burnFee);
    }

    function setCommonFee(uint fee) external onlyOwner {
        require(fee + commonBurnFee <= _DIVIDER, "Total fee should be in 0 - 100%");
        commonFotFee = fee;
    }

    function setBurnFee(uint fee) external onlyOwner {
        require(commonFotFee + fee <= _DIVIDER, "Total fee should be in 0 - 100%");
        commonBurnFee = fee;
    }

    function setBurnCycle(uint cycleLimit) external onlyOwner {
        burnCycleLimit = cycleLimit;
        emit BurnCycleLimitSet(burnCycleLimit);
    }

    function setRebaseDelta(uint delta) external onlyOwner {
        rebaseDelta = delta;
        emit RebaseDeltaSet(rebaseDelta);
    }

    function _rebase() internal {
        _actualTotal = _actualTotal + rebaseDelta;
        emit Rebase(rebaseDelta);
    }

    function recoverTokens(IERC20 token, address destination) external onlyOwner {
        require(destination != address(0), "Zero address not allowed");
        uint balance = token.balanceOf(address(this));
        if (balance > 0) {
            token.safeTransfer(destination, balance);
            emit TokensRecovered(address(token), destination, balance);
        }
    }
}