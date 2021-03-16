pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

interface IXknc {
  function mintWithToken(uint256 kncAmount) external;

  function burn(uint256 xkncToRedeem, bool redeemForKnc, uint256 minRate) external;

  function totalSupply() external view returns(uint);

  function getFundKncBalanceTwei() external view returns(uint); // staked knc balance
}

interface IController {
  function withdraw(address, uint256) external;

  function balanceOf(address) external view returns (uint256);

  function earn(address, uint256) external;

  function want(address) external view returns (address);

  function rewards() external view returns (address);

  function vaults(address) external view returns (address);

  function strategies(address) external view returns (address);
}


contract StrategyXknc {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;

  address public constant want = address(
    0x0bfEc35a1A3550Deed3F6fC76Dde7FC412729a91
  ); // xKNCa

  address public knc = address(
    0xdd974D5C2e2928deA5F71b9825b8b646686BD200
  );

  uint256 public earned;
  uint256 public performanceFee = 500;
  uint256 public withdrawalFee = 20;
  uint256 public constant FEE_DENOMINATOR = 10000;

  address public governance;
  address public controller;
  address public strategist;

  constructor(address _controller) {
    governance = msg.sender;
    strategist = msg.sender;
    controller = _controller;

    IERC20(knc).approve(want, uint(-1));
  }

  function getName() external pure returns (string memory) {
    return "StrategyXknc";
  }

  // called after every KyberDAO epoch (2 wks)
  function simulateHarvest() external {
    // TODO
  }

  function deposit() public {
    uint256 _want = IERC20(knc).balanceOf(address(this));
    if (_want > 0) {
        IXknc(want).mintWithToken(_want);
    }
  }

  function setStrategist(address _strategist) external {
    require(
        msg.sender == governance || msg.sender == strategist,
        "!authorized"
    );
    strategist = _strategist;
  }

  function setWithdrawalFee(uint256 _withdrawalFee) external {
    require(msg.sender == governance, "!governance");
    withdrawalFee = _withdrawalFee;
  }

  function setPerformanceFee(uint256 _performanceFee) external {
    require(msg.sender == governance, "!governance");
    performanceFee = _performanceFee;
  }

  // xknc balance
  function balanceOfWant() public view returns (uint256) {
    return IERC20(want).balanceOf(address(this));
  }

  // in knc terms
  function balanceOfBaseToken() public view returns (uint256) {
    return IERC20(knc).balanceOf(address(this));
  }

  // total balance in knc terms
  function balanceOf() public view returns (uint256) {
    IXknc xknc = IXknc(want);
    uint256 kncEquivalent = (xknc.getFundKncBalanceTwei()).mul(balanceOfWant()).div(xknc.totalSupply());
    return kncEquivalent.add(balanceOfBaseToken());
  }

  function setGovernance(address _governance) external {
    require(msg.sender == governance, "!governance");
    governance = _governance;
  }

  function setController(address _controller) external {
    require(msg.sender == governance, "!governance");
    controller = _controller;
  }

  // knc is doing a migration in a few months
  // we will handle this from the xKNC side, but you'll need to 
  // update knc address here
  function setKncAddress(address _knc) external {
    require(
      msg.sender == governance || msg.sender == strategist,
      "!authorized"
    );
    knc = _knc;
  }

  // Controller only function for creating additional rewards from dust
  function withdraw(IERC20 _asset) external returns (uint256 balance) {
    require(msg.sender == controller, "!controller");
    require(want != address(_asset), "want");
    require(knc != address(_asset), "knc");
    balance = _asset.balanceOf(address(this));
    _asset.safeTransfer(controller, balance);
  }

  // Withdraw partial funds, normally used with a vault withdrawal
  function withdrawKnc(uint256 _amount) external {
    require(msg.sender == controller, "!controller");

    uint256 _kncBalance = balanceOfBaseToken();
    require(_amount <= _kncBalance, "Balance unavailable");

    uint256 _fee = _amount.mul(withdrawalFee).div(FEE_DENOMINATOR);
    IERC20(knc).safeTransfer(IController(controller).rewards(), _fee);

    address _vault = IController(controller).vaults(address(want));
    require(_vault != address(0), "!vault");
    IERC20(want).safeTransfer(_vault, _amount.sub(_fee));
  }

  function withdrawXknc(uint256 _xkncAmount) external {
    require(msg.sender == controller, "!controller");
    IXknc(want).burn(_xkncAmount, true, 0);
  }

  // Withdraw all funds, normally used when migrating strategies
  function burnAndWithdrawAll() external {
    require(msg.sender == controller, "!controller");
    IXknc(want).burn(balanceOfWant(), true, 0);

    address _vault = IController(controller).vaults(address(want));
    require(_vault != address(0), "!vault");

    uint256 _kncBalance = balanceOfBaseToken();
    IERC20(knc).safeTransfer(_vault, _kncBalance);
  }

}
