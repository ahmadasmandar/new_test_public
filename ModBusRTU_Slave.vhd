----------------------------------------------------------------------------------
-- Copyright        :   Vietzke Engineering 2023
-- Developer        :   Tobias Vietzke
--
-- Module           :   ModBusRTU_Slave
-- Version          :   v1.00
-- Creation         :   2023-03-08
--
-- Description      :   ModBus RTU slave function for FC03 / FC06.
--                      Attention: !! FC03 returns on byte 3 always 0xFF !!
--
----------------------------------------------------------------------------------
--
-- Changelog:
--
--      v1.00 - Creation of file
--
----------------------------------------------------------------------------------
--
-- ToDos:
--
--      - Add timeout (back to state z_RX_SlaveAddress after xx ms no new data)
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ModBusRTU_Slave is
    Generic     (   gClock                  : INTEGER           := 50000000;                            --! set system clock frenqcy
                    gBaudRate               : INTEGER           :=  1000000;                            --! set uart baudrate
                    gSlaveAddress           : INTEGER           :=        1                             --! ModBus RTU slave address
                );
    Port        (   pClock                  : in    STD_LOGIC;                                          --! system clock input
                    pReset                  : in    STD_LOGIC;                                          --! asynchronous reset input

                    pRXD                    : in    STD_LOGIC;                                          --! rxd input
                    pTXD                    : out   STD_LOGIC;                                          --! txd output

                    pRegisterActiveAccess   : out   STD_LOGIC;                                          --! indicates a register access
                    pRegisterAddress        : out   STD_LOGIC_VECTOR(15 downto 0);                      --! address set by master message
                    pWriteRequest           : out   STD_LOGIC;                                          --! write trigger
                    pWriteData              : out   STD_LOGIC_VECTOR(15 downto 0);                      --! write data set by master message
                    pReadRequest            : out   STD_LOGIC;                                          --! read trigger
                    pReadData               : in    STD_LOGIC_VECTOR(15 downto 0)                       --! read data set by fpga
                );
end;

architecture Behavioral of ModBusRTU_Slave is

    -- ###############################################################################################
    -- ###############################################################################################
    -- ##                                                                                           ##
    -- ## Componenten declarations                                                                  ##
    -- ##                                                                                           ##
    -- ###############################################################################################
    -- ###############################################################################################

    component UART_Transceiver_v1_10 is
        Generic     (   gClock                  : INTEGER := 25000000;                                      --!
                        gUARTClock              : INTEGER := 1000000;                                       --!
                        gNumberOfBits           : INTEGER := 8;                                             --!
                        gNumberOfStopBits       : INTEGER := 1                                              --!
                    );
        Port        (   pClock                  : in    STD_LOGIC;                                          --!
                        pReset                  : in    STD_LOGIC;                                          --!

                        pTXD                    : out   STD_LOGIC;                                          --!
                        pRXD                    : in    STD_LOGIC;                                          --!

                        pTransmitStart          : in    STD_LOGIC;                                          --!
                        pTransmitReady          : out   STD_LOGIC;                                          --!
                        pTransmitData           : in    STD_LOGIC_VECTOR(7 downto 0);                       --!

                        pReceiveNewData         : out   STD_LOGIC;                                          --!
                        pReceiveData            : out   STD_LOGIC_VECTOR(7 downto 0)                        --!
                    );
    end component;

    -- ###############################################################################################
    -- ###############################################################################################
    -- ##                                                                                           ##
    -- ## Signal declarations                                                                       ##
    -- ##                                                                                           ##
    -- ###############################################################################################
    -- ###############################################################################################

    type tState is  (   z_RX_SlaveAddress,
                        z_RX_FunctionCode,
                        z_RX_AddressHighByte,
                        z_RX_AddressLowByte,
                        z_RX_DataHighByte,
                        z_RX_DataLowByte,
                        z_RX_CrcHighByte,
                        z_RX_CrcLowByte,
                        z_CheckCRC,
                        z_TX_SlaveAddress,
                        z_TX_FunctionCode,
                        z_TX_AddressHighByte,
                        z_TX_AddressLowByte,
                        z_TX_GetRegisterValue,
                        z_TX_GetRegisterValueWait,
                        z_TX_GetRegisterValueWait2,
                        z_TX_SendDataHighByte,
                        z_TX_SendDataLowByte,
                        z_TX_SendCRCHighByte,
                        z_TX_SendCRCLowByte
                    );

    signal          sCurrentState                       : tState;

    signal          sUARTTxStart                        : STD_LOGIC;
    signal          sUARTTxReady                        : STD_LOGIC;
    signal          sUARTTxData                         : STD_LOGIC_VECTOR(7 downto 0);
    signal          sUARTTxDataReverse                  : STD_LOGIC_VECTOR(7 downto 0);
    signal          sUARTRxNewData                      : STD_LOGIC;
    signal          sUARTRxData                         : STD_LOGIC_VECTOR(7 downto 0);
    signal          sUARTRxDataReverse                  : STD_LOGIC_VECTOR(7 downto 0);

    signal          sRegisterCounter                    : UNSIGNED(15 downto 0);
    signal          sFunctionCode                       : STD_LOGIC_VECTOR(7 downto 0);
    signal          sRegisterAddress                    : UNSIGNED(15 downto 0);
    signal          sRegisterData                       : STD_LOGIC_VECTOR(15 downto 0);
    signal          sMasterCRC                          : STD_LOGIC_VECTOR(15 downto 0);
    signal          sCalculatedCRC                      : STD_LOGIC_VECTOR(15 downto 0);
    signal          sCalculatedCRCReverse               : STD_LOGIC_VECTOR(15 downto 0);

begin

    -- ############################################################################################
    -- ############################################################################################
    -- ##                                                                                        ##
    -- ##  Component instances                                                                   ##
    -- ##                                                                                        ##
    -- ############################################################################################
    -- ############################################################################################

    UART_Transceiver_inst : UART_Transceiver_v1_10
        Generic Map (   gClock                  => gClock,
                        gUARTClock              => gBaudRate,
                        gNumberOfBits           => 8,
                        gNumberOfStopBits       => 2
                    )
        Port Map    (   pClock                  => pClock,
                        pReset                  => pReset,

                        pTXD                    => pTXD,
                        pRXD                    => pRXD,

                        pTransmitStart          => sUARTTxStart,
                        pTransmitReady          => sUARTTxReady,
                        pTransmitData           => sUARTTxData,

                        pReceiveNewData         => sUARTRxNewData,
                        pReceiveData            => sUARTRxData
                    );

    -- ############################################################################################
    -- ############################################################################################
    -- ##                                                                                        ##
    -- ##  Signal and io assignments                                                             ##
    -- ##                                                                                        ##
    -- ############################################################################################
    -- ############################################################################################

    sUARTRxDataReverse(7)           <= sUARTRxData(0);
    sUARTRxDataReverse(6)           <= sUARTRxData(1);
    sUARTRxDataReverse(5)           <= sUARTRxData(2);
    sUARTRxDataReverse(4)           <= sUARTRxData(3);
    sUARTRxDataReverse(3)           <= sUARTRxData(4);
    sUARTRxDataReverse(2)           <= sUARTRxData(5);
    sUARTRxDataReverse(1)           <= sUARTRxData(6);
    sUARTRxDataReverse(0)           <= sUARTRxData(7);

    sUARTTxDataReverse(7)           <= sUARTTxData(0);
    sUARTTxDataReverse(6)           <= sUARTTxData(1);
    sUARTTxDataReverse(5)           <= sUARTTxData(2);
    sUARTTxDataReverse(4)           <= sUARTTxData(3);
    sUARTTxDataReverse(3)           <= sUARTTxData(4);
    sUARTTxDataReverse(2)           <= sUARTTxData(5);
    sUARTTxDataReverse(1)           <= sUARTTxData(6);
    sUARTTxDataReverse(0)           <= sUARTTxData(7);

    sCalculatedCRCReverse(0)        <= sCalculatedCRC(15);
    sCalculatedCRCReverse(1)        <= sCalculatedCRC(14);
    sCalculatedCRCReverse(2)        <= sCalculatedCRC(13);
    sCalculatedCRCReverse(3)        <= sCalculatedCRC(12);
    sCalculatedCRCReverse(4)        <= sCalculatedCRC(11);
    sCalculatedCRCReverse(5)        <= sCalculatedCRC(10);
    sCalculatedCRCReverse(6)        <= sCalculatedCRC(9);
    sCalculatedCRCReverse(7)        <= sCalculatedCRC(8);
    sCalculatedCRCReverse(8)        <= sCalculatedCRC(7);
    sCalculatedCRCReverse(9)        <= sCalculatedCRC(6);
    sCalculatedCRCReverse(10)       <= sCalculatedCRC(5);
    sCalculatedCRCReverse(11)       <= sCalculatedCRC(4);
    sCalculatedCRCReverse(12)       <= sCalculatedCRC(3);
    sCalculatedCRCReverse(13)       <= sCalculatedCRC(2);
    sCalculatedCRCReverse(14)       <= sCalculatedCRC(1);
    sCalculatedCRCReverse(15)       <= sCalculatedCRC(0);

    sUARTTxStart                    <=  '1'                     when sCurrentState = z_TX_SlaveAddress else
                                        '1'                     when sCurrentState = z_TX_FunctionCode else
                                        '1'                     when sCurrentState = z_TX_AddressHighByte else
                                        '1'                     when sCurrentState = z_TX_AddressLowByte else
                                        '1'                     when sCurrentState = z_TX_SendDataHighByte else
                                        '1'                     when sCurrentState = z_TX_SendDataLowByte else
                                        '1'                     when sCurrentState = z_TX_SendCRCHighByte else
                                        '1'                     when sCurrentState = z_TX_SendCRCLowByte else
                                        '0';

    sUARTTxData                     <=  std_logic_vector(to_unsigned(gSlaveAddress, sUARTRxData'Length))    when sCurrentState = z_TX_SlaveAddress else
                                        sFunctionCode                                                       when sCurrentState = z_TX_FunctionCode else
                                        std_logic_vector(sRegisterAddress(15 downto 8))                     when sCurrentState = z_TX_AddressHighByte and sFunctionCode = X"06"  else
                                        X"FF"                                                               when sCurrentState = z_TX_AddressHighByte and sFunctionCode = X"03" else
                                        std_logic_vector(sRegisterAddress( 7 downto 0))                     when sCurrentState = z_TX_AddressLowByte else
                                        sRegisterData(15 downto 8)                                          when sCurrentState = z_TX_SendDataHighByte and sFunctionCode = X"06" else
                                        pReadData(15 downto 8)                                              when sCurrentState = z_TX_SendDataHighByte and sFunctionCode = X"03" else
                                        sRegisterData( 7 downto 0)                                          when sCurrentState = z_TX_SendDataLowByte and sFunctionCode = X"06" else
                                        pReadData( 7 downto 0)                                              when sCurrentState = z_TX_SendDataLowByte and sFunctionCode = X"03" else
                                        sCalculatedCRCReverse( 7 downto 0)                                  when sCurrentState = z_TX_SendCRCHighByte else
                                        sCalculatedCRCReverse(15 downto 8)                                  when sCurrentState = z_TX_SendCRCLowByte else
                                        X"00";

    pRegisterActiveAccess           <=  '0'                     when sCurrentState = z_RX_SlaveAddress else
                                        '1';

    pRegisterAddress                <=  std_logic_vector(sRegisterAddress);

    pWriteRequest                   <=  '1'                     when sCurrentState = z_TX_SlaveAddress else
                                        '0';

    pWriteData                      <=  sRegisterData;

    pReadRequest                    <=  '1'                     when sCurrentState = z_TX_GetRegisterValue else
                                        '0';

    -- ############################################################################################
    -- ############################################################################################
    -- ##                                                                                        ##
    -- ##  Processes                                                                             ##
    -- ##                                                                                        ##
    -- ############################################################################################
    -- ############################################################################################

    UARTRxProcess: process (pClock, pReset)
    begin
        if (pReset = '1') then
            sRegisterCounter    <= (others=>'0');
            sFunctionCode       <= (others=>'0');
            sRegisterAddress    <= (others=>'0');
            sRegisterData       <= (others=>'0');
            sMasterCRC          <= (others=>'0');
            sCurrentState       <= z_RX_SlaveAddress;
        elsif (rising_edge(pClock)) then

            case sCurrentState is
                when z_RX_SlaveAddress          =>  if (sUARTRxNewData = '1' and sUARTRxData = std_logic_vector(to_unsigned(gSlaveAddress, sUARTRxData'Length))) then
                                                        sCurrentState <= z_RX_FunctionCode;
                                                    else
                                                        sCurrentState <= z_RX_SlaveAddress;
                                                    end if;
                                                    sRegisterCounter <= to_unsigned(1, sRegisterCounter'Length);

                when z_RX_FunctionCode          =>  if (sUARTRxNewData = '1') then
                                                        if (sUARTRxData = X"03" or                      -- FC03 Read Holding Registers
                                                            sUARTRxData = X"06") then                   -- FC06 Preset Single Register
                                                            sCurrentState <= z_RX_AddressHighByte;
                                                        else
                                                            sCurrentState <= z_RX_SlaveAddress;
                                                        end if;
                                                    else
                                                        sCurrentState <= z_RX_FunctionCode;
                                                    end if;
                                                    sFunctionCode <= sUARTRxData;

                when z_RX_AddressHighByte       =>  if (sUARTRxNewData = '1') then
                                                        sCurrentState <= z_RX_AddressLowByte;
                                                        sRegisterAddress(15 downto 8) <= unsigned(sUARTRxData);
                                                    else
                                                        sCurrentState <= z_RX_AddressHighByte;
                                                    end if;

                when z_RX_AddressLowByte        =>  if (sUARTRxNewData = '1') then
                                                        sCurrentState <= z_RX_DataHighByte;
                                                        sRegisterAddress( 7 downto 0) <= unsigned(sUARTRxData);
                                                    else
                                                        sCurrentState <= z_RX_AddressLowByte;
                                                    end if;

                when z_RX_DataHighByte          =>  if (sUARTRxNewData = '1') then
                                                        sCurrentState <= z_RX_DataLowByte;
                                                        sRegisterData(15 downto 8) <= sUARTRxData;
                                                    else
                                                        sCurrentState <= z_RX_DataHighByte;
                                                    end if;

                when z_RX_DataLowByte           =>  if (sUARTRxNewData = '1') then
                                                        sCurrentState <= z_RX_CrcHighByte;
                                                        sRegisterData( 7 downto 0) <= sUARTRxData;
                                                    else
                                                        sCurrentState <= z_RX_DataLowByte;
                                                    end if;

                when z_RX_CrcHighByte           =>  if (sUARTRxNewData = '1') then
                                                        sCurrentState <= z_RX_CrcLowByte;
                                                        sMasterCRC(15 downto 8) <= sUARTRxData;
                                                    else
                                                        sCurrentState <= z_RX_CrcHighByte;
                                                    end if;

                when z_RX_CrcLowByte            =>  if (sUARTRxNewData = '1') then
                                                        sCurrentState <= z_CheckCRC;
                                                        sMasterCRC( 7 downto 0) <= sUARTRxData;
                                                    else
                                                        sCurrentState <= z_RX_CrcLowByte;
                                                    end if;

                when z_CheckCRC                 =>  if (sMasterCRC( 7 downto 0) = sCalculatedCRCReverse(15 downto 8) and
                                                        sMasterCRC(15 downto 8) = sCalculatedCRCReverse( 7 downto 0)) then
                                                        sCurrentState <= z_TX_SlaveAddress;
                                                    else
                                                        sCurrentState <= z_RX_SlaveAddress;
                                                    end if;

                when z_TX_SlaveAddress          =>  if (sUARTTxReady = '1') then
                                                        sCurrentState <= z_TX_FunctionCode;
                                                    else
                                                        sCurrentState <= z_TX_SlaveAddress;
                                                    end if;

                when z_TX_FunctionCode          =>  if (sUARTTxReady = '1') then
                                                        sCurrentState <= z_TX_AddressHighByte;
                                                    else
                                                        sCurrentState <= z_TX_FunctionCode;
                                                    end if;

                when z_TX_AddressHighByte       =>  if (sUARTTxReady = '1') then
                                                        if (sFunctionCode = X"03") then
                                                            sCurrentState <= z_TX_GetRegisterValue;   -- FC03 Read Holding Registers
                                                        else
                                                            sCurrentState <= z_TX_AddressLowByte;   -- FC06 Preset Single Register
                                                        end if;
                                                    else
                                                        sCurrentState <= z_TX_AddressHighByte;
                                                    end if;

                when z_TX_AddressLowByte        =>  if (sUARTTxReady = '1') then
                                                        sCurrentState <= z_TX_SendDataHighByte;
                                                    else
                                                        sCurrentState <= z_TX_AddressLowByte;
                                                    end if;

                when z_TX_GetRegisterValue      =>  sCurrentState <= z_TX_GetRegisterValueWait;

                when z_TX_GetRegisterValueWait  =>  sCurrentState <= z_TX_GetRegisterValueWait2;

                when z_TX_GetRegisterValueWait2 =>  sCurrentState <= z_TX_SendDataHighByte;

                when z_TX_SendDataHighByte      =>  if (sUARTTxReady = '1') then
                                                        sCurrentState <= z_TX_SendDataLowByte;
                                                    else
                                                        sCurrentState <= z_TX_SendDataHighByte;
                                                    end if;

                when z_TX_SendDataLowByte       =>  if (sUARTTxReady = '1') then
                                                        if (sFunctionCode = X"03") then         -- FC03 Read Holding Registers
                                                            sRegisterCounter <= sRegisterCounter + 1;
                                                            if (std_logic_vector(sRegisterCounter) = sRegisterData) then
                                                                sCurrentState <= z_TX_SendCRCHighByte;
                                                            else
                                                                sCurrentState <= z_TX_GetRegisterValue;
                                                                sRegisterAddress <= sRegisterAddress + 1;
                                                            end if;
                                                        else -- (sFunctionCode = X"06")         -- FC06 Preset Single Register
                                                            sCurrentState <= z_TX_SendCRCHighByte;
                                                        end if;
                                                    else
                                                        sCurrentState <= z_TX_SendDataLowByte;
                                                    end if;

                when z_TX_SendCRCHighByte       =>  if (sUARTTxReady = '1') then
                                                        sCurrentState <= z_TX_SendCRCLowByte;
                                                    else
                                                        sCurrentState <= z_TX_SendCRCHighByte;
                                                    end if;

                when z_TX_SendCRCLowByte        =>  if (sUARTTxReady = '1') then
                                                        sCurrentState <= z_RX_SlaveAddress;
                                                    else
                                                        sCurrentState <= z_TX_SendCRCLowByte;
                                                    end if;

                when others                     =>  sCurrentState <= z_RX_SlaveAddress;
            end case;
        end if;
    end process;


    CRCProcess: process (pClock, pReset)
    begin
        if (pReset = '1') then
            sCalculatedCRC <= (others =>'0');
        elsif (rising_edge(pClock)) then
            if ((sCurrentState = z_RX_SlaveAddress and sUARTRxNewData = '0') or sCurrentState = z_CheckCRC) then
                sCalculatedCRC <= (others =>'1');
            else
                if (sUARTRxNewData = '1' and sCurrentState /= z_RX_CrcHighByte and sCurrentState /= z_RX_CrcLowByte) then
                    sCalculatedCRC(0) <= sCalculatedCRC(8) xor sCalculatedCRC(9) xor sCalculatedCRC(10) xor sCalculatedCRC(11) xor sCalculatedCRC(12) xor sCalculatedCRC(13) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor sUARTRxDataReverse(0) xor  sUARTRxDataReverse(1) xor sUARTRxDataReverse(2) xor sUARTRxDataReverse(3) xor sUARTRxDataReverse(4) xor sUARTRxDataReverse(5) xor sUARTRxDataReverse(6) xor sUARTRxDataReverse(7);
                    sCalculatedCRC(1) <= sCalculatedCRC(9) xor sCalculatedCRC(10) xor sCalculatedCRC(11) xor sCalculatedCRC(12) xor sCalculatedCRC(13) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor sUARTRxDataReverse(1) xor sUARTRxDataReverse(2) xor  sUARTRxDataReverse(3) xor sUARTRxDataReverse(4) xor sUARTRxDataReverse(5) xor sUARTRxDataReverse(6) xor sUARTRxDataReverse(7);
                    sCalculatedCRC(2) <= sCalculatedCRC(8) xor sCalculatedCRC(9) xor sUARTRxDataReverse(0) xor sUARTRxDataReverse(1);
                    sCalculatedCRC(3) <= sCalculatedCRC(9) xor sCalculatedCRC(10) xor sUARTRxDataReverse(1) xor sUARTRxDataReverse(2);
                    sCalculatedCRC(4) <= sCalculatedCRC(10) xor sCalculatedCRC(11) xor sUARTRxDataReverse(2) xor sUARTRxDataReverse(3);
                    sCalculatedCRC(5) <= sCalculatedCRC(11) xor sCalculatedCRC(12) xor sUARTRxDataReverse(3) xor sUARTRxDataReverse(4);
                    sCalculatedCRC(6) <= sCalculatedCRC(12) xor sCalculatedCRC(13) xor sUARTRxDataReverse(4) xor sUARTRxDataReverse(5);
                    sCalculatedCRC(7) <= sCalculatedCRC(13) xor sCalculatedCRC(14) xor sUARTRxDataReverse(5) xor sUARTRxDataReverse(6);
                    sCalculatedCRC(8) <= sCalculatedCRC(0) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor sUARTRxDataReverse(6) xor sUARTRxDataReverse(7);
                    sCalculatedCRC(9) <= sCalculatedCRC(1) xor sCalculatedCRC(15) xor sUARTRxDataReverse(7);
                    sCalculatedCRC(10)<= sCalculatedCRC(2);
                    sCalculatedCRC(11)<= sCalculatedCRC(3);
                    sCalculatedCRC(12)<= sCalculatedCRC(4);
                    sCalculatedCRC(13)<= sCalculatedCRC(5);
                    sCalculatedCRC(14)<= sCalculatedCRC(6);
                    sCalculatedCRC(15)<= sCalculatedCRC(7) xor sCalculatedCRC(8) xor sCalculatedCRC(9) xor sCalculatedCRC(10) xor sCalculatedCRC(11) xor sCalculatedCRC(12) xor sCalculatedCRC(13) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor  sUARTRxDataReverse(0) xor sUARTRxDataReverse(1) xor sUARTRxDataReverse(2) xor sUARTRxDataReverse(3) xor sUARTRxDataReverse(4) xor sUARTRxDataReverse(5)  xor sUARTRxDataReverse(6) xor sUARTRxDataReverse(7);
                end if;
                if (sUARTTxReady = '1' and sCurrentState /= z_TX_SendCRCHighByte and sCurrentState /= z_TX_SendCRCLowByte) then
                    sCalculatedCRC(0) <= sCalculatedCRC(8) xor sCalculatedCRC(9) xor sCalculatedCRC(10) xor sCalculatedCRC(11) xor sCalculatedCRC(12) xor sCalculatedCRC(13) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor sUARTTxDataReverse(0) xor  sUARTTxDataReverse(1) xor sUARTTxDataReverse(2) xor sUARTTxDataReverse(3) xor sUARTTxDataReverse(4) xor sUARTTxDataReverse(5) xor sUARTTxDataReverse(6) xor sUARTTxDataReverse(7);
                    sCalculatedCRC(1) <= sCalculatedCRC(9) xor sCalculatedCRC(10) xor sCalculatedCRC(11) xor sCalculatedCRC(12) xor sCalculatedCRC(13) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor sUARTTxDataReverse(1) xor sUARTTxDataReverse(2) xor  sUARTTxDataReverse(3) xor sUARTTxDataReverse(4) xor sUARTTxDataReverse(5) xor sUARTTxDataReverse(6) xor sUARTTxDataReverse(7);
                    sCalculatedCRC(2) <= sCalculatedCRC(8) xor sCalculatedCRC(9) xor sUARTTxDataReverse(0) xor sUARTTxDataReverse(1);
                    sCalculatedCRC(3) <= sCalculatedCRC(9) xor sCalculatedCRC(10) xor sUARTTxDataReverse(1) xor sUARTTxDataReverse(2);
                    sCalculatedCRC(4) <= sCalculatedCRC(10) xor sCalculatedCRC(11) xor sUARTTxDataReverse(2) xor sUARTTxDataReverse(3);
                    sCalculatedCRC(5) <= sCalculatedCRC(11) xor sCalculatedCRC(12) xor sUARTTxDataReverse(3) xor sUARTTxDataReverse(4);
                    sCalculatedCRC(6) <= sCalculatedCRC(12) xor sCalculatedCRC(13) xor sUARTTxDataReverse(4) xor sUARTTxDataReverse(5);
                    sCalculatedCRC(7) <= sCalculatedCRC(13) xor sCalculatedCRC(14) xor sUARTTxDataReverse(5) xor sUARTTxDataReverse(6);
                    sCalculatedCRC(8) <= sCalculatedCRC(0) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor sUARTTxDataReverse(6) xor sUARTTxDataReverse(7);
                    sCalculatedCRC(9) <= sCalculatedCRC(1) xor sCalculatedCRC(15) xor sUARTTxDataReverse(7);
                    sCalculatedCRC(10)<= sCalculatedCRC(2);
                    sCalculatedCRC(11)<= sCalculatedCRC(3);
                    sCalculatedCRC(12)<= sCalculatedCRC(4);
                    sCalculatedCRC(13)<= sCalculatedCRC(5);
                    sCalculatedCRC(14)<= sCalculatedCRC(6);
                    sCalculatedCRC(15)<= sCalculatedCRC(7) xor sCalculatedCRC(8) xor sCalculatedCRC(9) xor sCalculatedCRC(10) xor sCalculatedCRC(11) xor sCalculatedCRC(12) xor sCalculatedCRC(13) xor sCalculatedCRC(14) xor sCalculatedCRC(15) xor  sUARTTxDataReverse(0) xor sUARTTxDataReverse(1) xor sUARTTxDataReverse(2) xor sUARTTxDataReverse(3) xor sUARTTxDataReverse(4) xor sUARTTxDataReverse(5)  xor sUARTTxDataReverse(6) xor sUARTTxDataReverse(7);
                end if;
            end if;
        end if;
    end process;

end architecture;

