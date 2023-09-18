----------------------------------------------------------------------------------
-- Firma            :   Vietzke Engineering
-- Ersteller        :   Tobias Vietzke
-- 
-- Modulname        :   UART_Transceiver
-- Projektname      :   -
-- Version          :   v1_10
-- Erstellung       :   03.02.2019
--
-- Beschreibung     :   Sendet und Empfaengt Daten mittels dem RS232 Protokoll 
--                      Es werden die Modi unterstuetzt: 
--                          * 5-8 Datenbits
--                          * Keine Parität
--                          * 1 oder 2 Stopbits
--               
----------------------------------------------------------------------------------
--
-- Dateihistorie
--     
--      v1_00 - Erstellung der Datei
--      v1_10 - RX war ein Takt falsch
--
----------------------------------------------------------------------------------
--
-- ToDos
--     
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_Transceiver_v1_10 is
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
end;

architecture Behavioral of UART_Transceiver_v1_10 is

    -- ###############################################################################################
    -- ###############################################################################################
    -- ##                                                                                           ##
    -- ## Signaldeklarationen                                                                       ##
    -- ##                                                                                           ##
    -- ###############################################################################################
    -- ###############################################################################################

    signal          sTXD                                : STD_LOGIC;                                                 
    signal          sTransmitCounter                    : INTEGER range 0 to ((gClock/gUARTClock)+1);
    signal          sTransmitShiftBit                   : INTEGER range 0 to (1+gNumberOfBits+gNumberOfStopBits+2);  
    signal          sTransmitStart                      : STD_LOGIC;                                                 
    signal          sTransmitReady                      : STD_LOGIC;                                                 
    signal          sTransmitNewBitTime                 : STD_LOGIC;
            
    signal          sRXD                                : STD_LOGIC;
    signal          sReceiveCounter                     : INTEGER range 0 to ((gClock/gUARTClock)+1);
    signal          sReceiveShiftBit                    : INTEGER range 0 to (1+gNumberOfBits+1);
    signal          sReceiveReady                       : STD_LOGIC;
    signal          sReceiveNewBitTime                  : STD_LOGIC;
    signal          sReceiveData                        : STD_LOGIC_VECTOR( 7 downto  0);

begin

    -- ############################################################################################
    -- ############################################################################################
    -- ##                                                                                        ##
    -- ##  Signal- und IO Zuweisungen                                                            ##
    -- ##                                                                                        ##
    -- ############################################################################################
    -- ############################################################################################

    pTransmitReady  <= sTransmitReady;
    pTXD            <= sTXD;
    pReceiveData    <= sReceiveData;
    pReceiveNewData <= sReceiveReady;
    
    -- ############################################################################################
    -- ############################################################################################
    -- ##                                                                                        ##
    -- ##  Prozesse                                                                              ##
    -- ##                                                                                        ##
    -- ############################################################################################
    -- ############################################################################################    
    TransmitStartBitProcess: process(pClock, pReset)
    begin
        if (pReset = '1') then 
            sTransmitStart <= '0';
            sTransmitReady <= '0';
        elsif (rising_edge(pClock)) then
            if (sTransmitReady = '1') then
                sTransmitReady <= '0';
                sTransmitStart <= '0';
            elsif (pTransmitStart = '1' and sTransmitStart = '0') then
                sTransmitStart <= '1';
            elsif (sTransmitShiftBit = (gNumberOfBits+gNumberOfStopBits + 2) and sTransmitStart = '1') then
                sTransmitStart <= '0';
                sTransmitReady <= '1';
            end if;
        end if;
    end process;
   
    TransmitShiftOutProcess: process(pClock, pReset)
    begin
        if (pReset = '1') then 
            sTXD                <= '1';
            sTransmitShiftBit   <= 0;
        elsif (rising_edge(pClock)) then
            if (sTransmitReady = '1') then
                    sTransmitShiftBit <= 0;
            elsif (sTransmitNewBitTime = '1') then
                if (sTransmitShiftBit = 0) then
                    sTXD <= '0';                                                                  
                elsif (sTransmitShiftBit > 0 and sTransmitShiftBit < gNumberOfBits + 1) then
                    sTXD <= pTransmitData(sTransmitShiftBit-1);                                   
                else
                    sTXD <= '1';                                                                  
                end if;
                sTransmitShiftBit <= sTransmitShiftBit + 1;
            end if;
        end if;
    end process;
    
    TransmitCounterProcess: process(pClock, pReset)
    begin
        if (pReset = '1') then 
            sTransmitCounter    <= 0;
            sTransmitNewBitTime <= '0';
        elsif (rising_edge(pClock)) then
            if (sTransmitStart = '0') then
                if (pTransmitStart = '1' and sTransmitReady='0') then
                    sTransmitNewBitTime <= '1';
                else
                    sTransmitNewBitTime <= '0'; 
                end if;
                sTransmitCounter <= 0;
            else
                if ((sTransmitCounter+1) = gClock / gUARTClock) then
                    if (sTransmitNewBitTime = '1') then
                        sTransmitNewBitTime <= '0';
                        sTransmitCounter <= 1; 
                    else
                        sTransmitNewBitTime <= '1';
                    end if;
                else
                    sTransmitNewBitTime <= '0';
                    sTransmitCounter <= sTransmitCounter + 1;
                end if;
            end if;
        end if;
    end process;
  
    ReceiveStartBitProcess: process(pClock, pReset)
    begin
        if (pReset = '1') then 
            sRXD            <= '1';
            sReceiveReady   <= '0';
        elsif (rising_edge(pClock)) then
            if (sReceiveReady = '1') then
                sReceiveReady <= '0';
                sRXD <= '1';
            elsif (pRXD = '0' and sRXD = '1') then
                sRXD <= '0';
            elsif (sReceiveShiftBit = (1 + gNumberOfBits + 1) and sRXD = '0') then
                sRXD <= '1';
                sReceiveReady <= '1';
            end if;
        end if;
    end process;
    
    ReceiveShiftInProcess: process(pClock, pReset)
    begin
        if (pReset = '1') then 
            sReceiveData        <= (others=>'0');
            sReceiveShiftBit    <= 0;
        elsif (rising_edge(pClock)) then
            if (sReceiveReady = '1') then
                sReceiveShiftBit <= 0;
            elsif (sReceiveNewBitTime = '1') then
                if (sReceiveShiftBit > 0 and sReceiveShiftBit < gNumberOfBits + 1) then
                    sReceiveData(sReceiveShiftBit-1) <= pRXD;                                                    
                end if;
                sReceiveShiftBit <= sReceiveShiftBit + 1;
            end if;
        end if;
    end process;
        
    ReceiveCounterProcess: process(pClock, pReset)
    begin
        if (pReset = '1') then 
            sReceiveCounter     <= 0;
            sReceiveNewBitTime  <= '0';
        elsif (rising_edge(pClock)) then
            if (sRXD = '1') then
                sReceiveCounter <= (gClock / gUARTClock) / 2;
            else
                if ((sReceiveCounter+2) = gClock / gUARTClock) then
                    if (sReceiveNewBitTime = '1') then
                        sReceiveNewBitTime <= '0';
                        sReceiveCounter <= 0; 
                    else
                        sReceiveNewBitTime <= '1';
                    end if;
                else
                    sReceiveNewBitTime <= '0';
                    sReceiveCounter <= sReceiveCounter + 1;
                end if;
            end if;
        end if;
    end process;
  
end architecture;