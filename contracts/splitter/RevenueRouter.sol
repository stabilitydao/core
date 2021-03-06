// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/ISplitter.sol";
import "../interfaces/IPayer.sol";
import "../libraries/FixidityLib.sol";
import "../interfaces/dexs.sol";

contract RevenueRouter is OwnableUpgradeable, UUPSUpgradeable {
    using FixidityLib for int256;

    address public PROFIT;
    address public BASE;
    uint24 public BASE_FEE;
    ISplitter public splitter;
    IPayer public profitPayer;
    IUniswapV3Router public v3Router;
    IUniswapV3Factory private v3Factory;

    /**
     * @dev Route to swap revenue token to PROFIT on Uniswap V3 DEX
     */
    struct V3Route {
        // @dev revenue token which we need to swap to PROFIT
        address inputToken;

        // @dev output token can be BASE or paired with BASE token on v3Router pools
        address outputToken;

        // @dev input-output pair LP pool fee, used only when outputToken is not BASE
        uint24 poolFee;

        // @dev output-base pair LP pool fee, used only when outputToken is not BASE
        uint24 outputBasePoolFee;

        // @dev route can be decativated
        bool active;
    }

    /**
     * @dev Route to swap revenue token to other token on Uniswap V2 DEX
     */
    struct V2Route {
        // @dev revenue token which we need to swap to PROFIT
        address inputToken;

        // @dev output token can be BASE, paired with BASE token on v2Router or any V3Route input token
        address outputToken;

        // @dev Uniswap V2 router
        address v2Router;

        // @dev swap outputToken to BASE through this v2Router
        bool swapToBase;

        // @dev route can be decativated
        bool active;
    }

    /**
     * @dev Route to send revenue tokens without swaps
     */
    struct DirectRoute {
        // @dev revenue token
        address token;

        // @dev send to
        address to;

        // @dev route can be decativated
        bool active;
    }

    V3Route[] public v3Routes;
    V2Route[] public v2Routes;
    DirectRoute[] public directRoutes;

    event ProfitGeneration(uint256 amount);
    event Send(address indexed token, address indexed to, uint256 amount);
    event V3RouteAdded(address indexed inputToken, address indexed outputToken, uint24 poolFee, uint24 outputBasePoolFee);
    event V3RouteUpdated(uint256 routeIndex, address inputToken, address outputToken, uint24 poolFee, uint24 outputBasePoolFee, bool active);
    event V3RouteDeleted(uint256 routeIndex);
    event V2RouteAdded(address indexed inputToken, address indexed outputToken, address indexed router);
    event V2RouteUpdated(uint256 routeIndex, address inputToken, address outputToken, address v2Router, bool active, bool swapToBase);
    event V2RouteDeleted(uint256 routeIndex);
    event DirectRouteAdded(address indexed token, address to);
    event DirectRouteUpdated(uint256 routeIndex, address token, address to, bool active);
    event DirectRouteDeleted(uint256 routeIndex);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {
        // solhint-disable-previous-line no-empty-blocks
    }

    function initialize(
        address PROFIT_,
        address BASE_,
        uint24 BASE_FEE_,
        IUniswapV3Factory factory_,
        IUniswapV3Router v3Router_,
        ISplitter splitter_,
        IPayer profitPayer_
    ) public initializer {
        PROFIT = PROFIT_;
        BASE = BASE_;
        BASE_FEE = BASE_FEE_;
        v3Factory = factory_;
        v3Router = v3Router_;
        splitter = splitter_;
        profitPayer = profitPayer_;
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    // important to receive ETH
    receive() external payable {}

    function totalV3Routes() external view returns (uint256) {
        return v3Routes.length;
    }

    function totalV2Routes() external view returns (uint256) {
        return v2Routes.length;
    }

    function totalDirectRoutes() external view returns (uint256) {
        return directRoutes.length;
    }

    // Add a new token to list of tokens that can be swapped to PROFIT.
    function addV3Route(address inputToken_, address outputToken_, uint24 poolFee_, uint24 outputBasePoolFee_) external onlyOwner {
        v3Routes.push(
            V3Route({
        inputToken: inputToken_,
        outputToken: outputToken_,
        poolFee: poolFee_,
        outputBasePoolFee: outputBasePoolFee_,
        active: true
        })
        );

        emit V3RouteAdded(inputToken_, outputToken_, poolFee_, outputBasePoolFee_);
    }

    function addV2Route(address inputToken_, address outputToken_, address v2Router_, bool swapToBase_) external onlyOwner {
        v2Routes.push(
            V2Route({
        inputToken: inputToken_,
        outputToken: outputToken_,
        v2Router: v2Router_,
        swapToBase: swapToBase_,
        active: true
        })
        );

        emit V2RouteAdded(inputToken_, outputToken_, v2Router_);
    }

    function addDirectRoute(address token_, address to_) external onlyOwner {
        directRoutes.push(
            DirectRoute({
        token: token_,
        to: to_,
        active: true
        })
        );

        emit DirectRouteAdded(token_, to_);
    }

    // function to remove tokenIn (spends less gas)
    function deleteV3Route(uint256 index_) external onlyOwner {
        require(index_ < v3Routes.length, "index out of bound");
        v3Routes[index_] = v3Routes[v3Routes.length - 1];
        v3Routes.pop();

        emit V3RouteDeleted(index_);
    }

    function deleteV2Route(uint256 index_) external onlyOwner {
        require(index_ < v2Routes.length, "index out of bound");
        v2Routes[index_] = v2Routes[v2Routes.length - 1];
        v2Routes.pop();

        emit V2RouteDeleted(index_);
    }

    function deleteDirectRoute(uint256 index_) external onlyOwner {
        require(index_ < directRoutes.length, "index out of bound");
        directRoutes[index_] = directRoutes[directRoutes.length - 1];
        directRoutes.pop();

        emit DirectRouteDeleted(index_);
    }

    function updateV3Route(uint256 index_, address inputToken_, address outputToken_, uint24 poolFee_, uint24 outputBasePoolFee_, bool active_) external onlyOwner {
        v3Routes[index_].inputToken = inputToken_;
        v3Routes[index_].outputToken = outputToken_;
        v3Routes[index_].poolFee = poolFee_;
        v3Routes[index_].outputBasePoolFee = outputBasePoolFee_;
        v3Routes[index_].active = active_;
        emit V3RouteUpdated(index_, inputToken_, outputToken_, poolFee_, outputBasePoolFee_, active_);
    }

    function updateV2Route(uint256 index_,  address inputToken_, address outputToken_, address v2Router_, bool active_, bool swapToBase_) external onlyOwner {
        v2Routes[index_].inputToken = inputToken_;
        v2Routes[index_].outputToken = outputToken_;
        v2Routes[index_].v2Router = v2Router_;
        v2Routes[index_].swapToBase = swapToBase_;
        v2Routes[index_].active = active_;
        emit V2RouteUpdated(index_, inputToken_, outputToken_, v2Router_, active_, swapToBase_);
    }

    function updateDirectRoute(uint256 index_,  address token_, address to_, bool active_) external onlyOwner {
        directRoutes[index_].token = token_;
        directRoutes[index_].to = to_;
        directRoutes[index_].active = active_;
        emit DirectRouteUpdated(index_, token_, to_, active_);
    }

    function run() external {
        sendTokens();
        uint256 amount = swapTokens();
        if (amount > 0) {
            splitter.run(address(PROFIT), address(profitPayer));
            emit ProfitGeneration(amount);
        }
    }

    function sendTokens() public {
        for (uint256 i = 0; i < directRoutes.length; i++) {
            DirectRoute storage directroute = directRoutes[i];

            if (directroute.active == false) {
                continue;
            }

            uint256 tokenBal = IERC20Upgradeable(directroute.token).balanceOf(address(this));
            if (tokenBal > 0) {
                IERC20Upgradeable(directroute.token).transfer(directroute.to, tokenBal);
                emit Send(directroute.token, directroute.to, tokenBal);
            }
        }
    }

    function swapTokens() public returns (uint256 amountOut) {
        uint256 amount;
        uint256 i;

        for (i = 0; i < v2Routes.length; i++) {
            V2Route storage v2route = v2Routes[i];

            if (v2route.active == false) {
                continue;
            }

            uint256 tokenBal = IERC20Upgradeable(v2route.inputToken).balanceOf(address(this));
            if (tokenBal > 0) {
                address[] memory path = new address[](2);
                path[0] = v2route.inputToken;
                path[1] = v2route.outputToken;
                if (IERC20Upgradeable(v2route.inputToken).allowance(address(this), v2route.v2Router) < tokenBal) {
                    safeApprove(v2route.inputToken, v2route.v2Router, type(uint256).max);
                }

                amount = IUniswapV2Router(v2route.v2Router).swapExactTokensForTokens(tokenBal, 0, path, address(this), block.timestamp)[1];

                if (v2route.outputToken != BASE && v2route.swapToBase) {
                    path[0] = v2route.outputToken;
                    path[1] = BASE;
                    if (IERC20Upgradeable(v2route.outputToken).allowance(address(this), v2route.v2Router) < amount) {
                        safeApprove(v2route.outputToken, v2route.v2Router, type(uint256).max);
                    }

                    amount = IUniswapV2Router(v2route.v2Router).swapExactTokensForTokens(amount, 0, path, address(this), block.timestamp)[1];
                }

                if (v2route.outputToken == BASE || v2route.swapToBase) {
                    // Swap WETH to PROFIT on v3
                    IUniswapV3Router.ExactInputSingleParams memory params2 = IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: BASE,
                    tokenOut: PROFIT,
                    fee: BASE_FEE,
                    recipient: address(splitter),
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                    });
                    // approve dexRouter to spend WETH
                    if (IERC20Upgradeable(BASE).allowance(address(this), address(v3Router)) < amount) {
                        safeApprove(BASE, address(v3Router), type(uint256).max);
                    }
                    amountOut += v3Router.exactInputSingle(params2);
                }
            }
        }

        for (i = 0; i < v3Routes.length; i++) {
            V3Route storage v3route = v3Routes[i];

            if (v3route.active == false) {
                continue;
            }

            uint256 tokenBal = IERC20Upgradeable(v3route.inputToken).balanceOf(address(this));

            if (tokenBal > 0) {
                // If TOKEN is Paired with BASE token (WETH now)
                if (v3route.outputToken == BASE) {
                    // Swap TOKEN to BASE
                    IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: v3route.inputToken,
                    tokenOut: BASE,
                    fee: BASE_FEE,
                    recipient: address(this),
                    amountIn: tokenBal,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                    });

                    // approve dexRouter to spend tokens
                    if (IERC20Upgradeable(v3route.inputToken).allowance(address(this), address(v3Router)) < tokenBal) {
                        safeApprove(v3route.inputToken, address(v3Router), type(uint256).max);
                    }

                    amount = v3Router.exactInputSingle(params);
                } else {
                    // TOKEN is Paired with v3route.outputToken
                    // Swap TOKEN to v3route.outputToken
                    IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: v3route.inputToken,
                    tokenOut: v3route.outputToken,
                    fee: v3route.poolFee,
                    recipient: address(this),
                    amountIn: tokenBal,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                    });

                    // approve dexRouter to spend TOKEN
                    if (IERC20Upgradeable(v3route.inputToken).allowance(address(this), address(v3Router)) < tokenBal) {
                        safeApprove(v3route.inputToken, address(v3Router), type(uint256).max);
                    }

                    amount = v3Router.exactInputSingle(params);

                    // Swap v3route.outputToken to BASE
                    IUniswapV3Router.ExactInputSingleParams memory params2 = IUniswapV3Router.ExactInputSingleParams({
                    tokenIn: v3route.outputToken,
                    tokenOut: BASE,
                    fee: v3route.outputBasePoolFee,
                    recipient: address(this),
                    amountIn: amount,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                    });

                    // approve dexRouter to spend outputToken
                    if (IERC20Upgradeable(v3route.outputToken).allowance(address(this), address(v3Router)) < amount) {
                        safeApprove(v3route.outputToken, address(v3Router), type(uint256).max);
                    }

                    amount = v3Router.exactInputSingle(params2);
                }

                // Swap BASE to PROFIT
                IUniswapV3Router.ExactInputSingleParams memory params3 = IUniswapV3Router.ExactInputSingleParams({
                tokenIn: BASE,
                tokenOut: PROFIT,
                fee: BASE_FEE,
                recipient: address(splitter),
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
                });
                // approve dexRouter to spend WETH
                if (IERC20Upgradeable(BASE).allowance(address(this), address(v3Router)) < amount) {
                    safeApprove(BASE, address(v3Router), type(uint256).max);
                }
                amountOut += v3Router.exactInputSingle(params3);
            }
        }
    }

    function withdrawERC20(address _token, address _to, uint256 _amount) public onlyOwner {
        IERC20Upgradeable(_token).transfer(_to, _amount);
    }

    function withdrawETH(address _to, uint256 ethAmount) public onlyOwner returns (bool success) {
        (success,) =  _to.call{value: ethAmount}("");
        require(success, "Failed to send Ether");
    }

    function getOutputAmount(uint amountIn, address tokenIn, address tokenOut, uint24 poolFee) public view returns (uint amountOut) {
        require(tokenIn != tokenOut, "tokenIn == tokenOut");
        uint tokenOutPrice;
        (address token0, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        IUniswapV3Pool pool = IUniswapV3Pool(v3Factory.getPool(token0, token1, poolFee));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        if (tokenOut == token1) {
            // tokenOutPrice = uint256((sqrtPriceX96 / 2**96) * (sqrtPriceX96 / 2**96));
            uint sqrtPrice = uint(sqrtPriceX96);
            int sqrtPriceInt = int(sqrtPrice);
            int denominator1 = int(2**76);
            int denominator2 = int(2**20);
            int x = sqrtPriceInt.divide(denominator1);
            int y = x.divide(denominator2);
            int out = ((y/1E24) * (y/1E24)) / int(1E24);
            // If tokenOut == token1, we have to divide amountOut by 1E24.
            tokenOutPrice = uint(out);
        } else if (tokenOut == token0) {
            // uint256 price = uint256((sqrtPriceX96 / 2**96) * (sqrtPriceX96 / 2**96));
            uint sqrtPrice = uint(sqrtPriceX96);
            int sqrtPriceInt = int(sqrtPrice);
            int denominator1 = int(2**76);
            int denominator2 = int(2**20);
            int x = sqrtPriceInt.divide(denominator1);
            int y = x.divide(denominator2);
            int price = ((y/1E24) * (y/1E24)) / int(1E24);
            int out = int(1).divide(price);
            tokenOutPrice = uint(out);
        }
        amountOut = uint(amountIn * tokenOutPrice);
    }

    function estimateProfit() external view returns (uint256 estimatedOutput) {
        uint256 amount;
        uint256 i;
        address tokenIn;
        address tokenOut;
        uint24 fee;
        uint256 amountIn;
        uint256 output;

        for (i = 0; i < v2Routes.length; i++) {
            V2Route storage v2route = v2Routes[i];

            if (v2route.active == false) {
                continue;
            }

            uint256 tokenBal = IERC20Upgradeable(v2route.inputToken).balanceOf(address(this));
            if (tokenBal > 0) {
                address[] memory path = new address[](2);
                path[0] = v2route.inputToken;
                path[1] = v2route.outputToken;

                amount = IUniswapV2Router(v2route.v2Router).getAmountsOut(tokenBal, path)[1];

                if (v2route.outputToken != BASE && v2route.swapToBase) {
                    path[0] = v2route.outputToken;
                    path[1] = BASE;

                    amount = IUniswapV2Router(v2route.v2Router).getAmountsOut(amount, path)[1];
                }

                if (v2route.outputToken == BASE || v2route.outputToken != BASE) {
                    // Estimate output for swap of BASE to PROFIT on v3
                    tokenIn = BASE;
                    tokenOut = PROFIT;
                    fee = BASE_FEE;
                    amountIn = amount;
                    (, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
                    
                    if (tokenOut == token1) {
                        uint256 outputAmt = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                        output = outputAmt/1E24;
                        estimatedOutput += output;
                    } else {
                        estimatedOutput += getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                    }                    
                }
            }
        }

        for (i = 0; i < v3Routes.length; i++) {
            V3Route storage v3route = v3Routes[i];

            if (v3route.active == false) {
                continue;
            }

            uint256 tokenBal = IERC20Upgradeable(v3route.inputToken).balanceOf(address(this));

            if (tokenBal > 0) {
                // If TOKEN is Paired with BASE token (WETH now)
                if (v3route.outputToken == BASE) {
                    // Estimate amountOut for swap of TOKEN to BASE on v3
                    tokenIn = v3route.inputToken;
                    tokenOut = BASE;
                    fee = v3route.poolFee;
                    amountIn = tokenBal;
                    (, address token2) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
                    
                    if (tokenOut == token2) {
                        uint256 outputAmt = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                        output = outputAmt/1E24;
                        amount = output;
                    } else {
                        amount = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                    }
                } else {
                    // TOKEN is Paired with v3route.outputToken
                    // Estimate amountOut for swap of TOKEN to v3route.outputToken on v3
                    tokenIn  = v3route.inputToken;
                    tokenOut = v3route.outputToken;
                    fee = v3route.poolFee;
                    amountIn = tokenBal;
                    (, address token3) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);                    
                    
                    if (tokenOut == token3) {
                        uint256 outputAmt = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                        output = outputAmt/1E24;
                        amount = output;
                    } else {
                        amount = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                    }

                    // Estimate amountOut for swap of v3route.outputToken to BASE on v3
                    tokenIn  = v3route.outputToken;
                    tokenOut = BASE;
                    fee = v3route.outputBasePoolFee;
                    amountIn = amount;
                    (, address token4) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);                    

                    if (tokenOut == token4) {                        
                        uint256 outputAmt = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                        output = outputAmt/1E24;
                        amount = output;
                    } else {
                        amount = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                    }
                }

                // Estimate amountOut for swap of BASE to PROFIT on v3
                tokenIn  = BASE;
                tokenOut = PROFIT;
                fee = BASE_FEE;
                amountIn = amount;
                (, address token5) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);                                
                if (tokenOut == token5) {                    
                    uint256 outputAmt = getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                    output = outputAmt/1E24;
                    estimatedOutput += output;                    
                } else {
                    estimatedOutput += getOutputAmount(amountIn, tokenIn, tokenOut, fee);
                }
            }
        }
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Upgradeable.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SA");
    }

    function reInit(
        address PROFIT_,
        address BASE_,
        uint24 BASE_FEE_,
        IUniswapV3Factory factory_,
        IUniswapV3Router v3Router_,
        ISplitter splitter_,
        IPayer profitPayer_
    ) external onlyOwner {
        PROFIT = PROFIT_;
        BASE = BASE_;
        BASE_FEE = BASE_FEE_;
        v3Factory = factory_;
        v3Router = v3Router_;
        splitter = splitter_;
        profitPayer = profitPayer_;
    }

    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {
        // solhint-disable-previous-line no-empty-blocks
    }
}