import { useState, useEffect } from "react";
import {
  Button,
  useColorMode,
  Flex,
  Heading,
  Spacer,
  Container,
  FormControl,
  FormLabel,
  InputGroup,
  Input,
  Center,
  useToast,
  Image,
  Box,
  Link,
  Text,
  VStack,
  InputRightElement,
  HStack,
} from "@chakra-ui/react";
import { ExternalLinkIcon } from "@chakra-ui/icons";
import { SunIcon, MoonIcon } from "@chakra-ui/icons";
import ConnectWallet, { targetNetwork } from "./components/ConnectWallet";
import { Contract, ethers, BigNumber } from "ethers";
import { Web3Provider, Signer } from "./types";
import Footer from "./components/Footer";
import { formatNumber, toDecimal } from "./utils";
import { parseEther } from "@ethersproject/units";
import { MaxUint256 } from "@ethersproject/constants";

function App() {
  const { colorMode, toggleColorMode } = useColorMode();
  const underlineColor = { light: "gray.500", dark: "gray.400" };
  const bgColor = { light: "white", dark: "gray.700" };
  const toast = useToast();

  const [provider, setProvider] = useState<Web3Provider>();
  const [signer, setSigner] = useState<Signer>();
  const [signerAddress, setSignerAddress] = useState<string>();
  const [amountToBridge, setAmountToBridge] = useState<BigNumber>(
    BigNumber.from(0)
  );
  const [v1Balance, setV1Balance] = useState<BigNumber>(BigNumber.from(0));

  const [v1Token, setV1Token] = useState<Contract>();
  const [v2Token, setV2Token] = useState<Contract>();
  const [tokenSwap, setTokenSwap] = useState<Contract>();
  const [loading, setLoading] = useState<boolean>(false);

  const { v1TokenAddress, v2TokenAddress, tokenSwapAddress } = targetNetwork;

  const ERC20ABI = require("./abi/ERC20.json");
  const TokenSwapABI = require("./abi/TokenSwap.json");

  // Initialize Contracts
  useEffect(() => {
    if (provider) {
      setV1Token(new ethers.Contract(v1TokenAddress, ERC20ABI, provider));
      setV2Token(new ethers.Contract(v2TokenAddress, ERC20ABI, provider));
      setTokenSwap(
        new ethers.Contract(tokenSwapAddress, TokenSwapABI, provider)
      );

      setSigner(provider.getSigner(0));
    }
  }, [provider]);

  // Get signer address
  useEffect(() => {
    const getSignerAddress = async () => {
      if (signer) {
        setSignerAddress(await signer.getAddress());
      }
    };

    getSignerAddress();
  }, [signer]);

  useEffect(() => {
    if (signerAddress) {
      fetchUserBalance();
    }
  }, [signerAddress]);

  const fetchUserBalance = async () => {
    setV1Balance(await v1Token!.balanceOf(signerAddress));
  };

  const bridge = async () => {
    setLoading(true);

    const allowance = await v1Token!.allowance(signerAddress, tokenSwapAddress);
    if (allowance.lt(amountToBridge)) {
      try {
        const approveTxn = await v1Token!
          .connect(signer!)
          .approve(tokenSwapAddress, MaxUint256);
        await approveTxn.wait();
      } catch {
        errorToast("Can't Approve");
        setLoading(false);
        return;
      }
    }
    try {
      const tx = await tokenSwap!.connect(signer!).bridge(amountToBridge);
      await tx.wait();
      await fetchUserBalance();
    } catch {
      errorToast("Can't Bridge");
    }
    setLoading(false);
  };

  const errorToast = (title: string, description: string = "") => {
    toast({
      title,
      description,
      status: "error",
      isClosable: true,
      duration: 3000,
    });
  };

  return (
    <>
      <Flex
        py="4"
        px={["2", "4", "10", "10"]}
        borderBottom="2px"
        borderBottomColor={underlineColor[colorMode]}
      >
        <Spacer flex="1" />
        <Heading maxW={["302px", "4xl", "4xl", "4xl"]}>
          Bridge V1 {"->"} V2 Tokens
        </Heading>
        <Flex flex="1" justifyContent="flex-end">
          <Button onClick={toggleColorMode} rounded="full" h="40px" w="40px">
            {colorMode === "light" ? <MoonIcon /> : <SunIcon />}
          </Button>
        </Flex>
      </Flex>
      <Container my="16" minH="md" minW={["0", "0", "2xl", "2xl"]}>
        <FormControl>
          <FormLabel>
            <HStack>
              <Text>Enter V1 Token Amount to Bridge</Text>
              <Spacer />
              <Text color="gray.300">
                Balance: {formatNumber(v1Balance, 18)}
              </Text>
            </HStack>
          </FormLabel>
          <InputGroup>
            <Input
              type="number"
              aria-label="v1-token-amount"
              placeholder="0"
              autoComplete="off"
              textAlign="right"
              value={toDecimal(amountToBridge, 18)}
              onChange={(e) => {
                let amt = e.target.value;
                if (!amt) amt = "0";
                setAmountToBridge(parseEther(amt));
              }}
              bg={bgColor[colorMode]}
              isDisabled={!signerAddress}
              pr="5.5rem"
            />
            <InputRightElement w="4.5rem" mr="0.1rem">
              <Button
                h="1.75rem"
                size="sm"
                onClick={() => setAmountToBridge(v1Balance)}
                isDisabled={!signerAddress}
              >
                Max
              </Button>
            </InputRightElement>
          </InputGroup>
        </FormControl>
        {signerAddress && (
          <Center pl="1rem">
            <Button
              isLoading={loading}
              pl="1rem"
              mt="1rem"
              onClick={() => {
                bridge();
              }}
            >
              Bridge 🔁
            </Button>
          </Center>
        )}
        <Center>
          {!provider && <ConnectWallet mt="10rem" setProvider={setProvider} />}
        </Center>
      </Container>
      <Footer />
    </>
  );
}

export default App;
