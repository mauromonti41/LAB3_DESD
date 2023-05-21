library IEEE;
    use IEEE.STD_LOGIC_1164.ALL;
    use IEEE.math_real.all;
    use IEEE.numeric_std.all;

    --test comment
entity volume_controller is
    
	generic (
		N_VALUE		    : integer := 6 
        );
	Port ( 
        -- 
		aclk 			: in  STD_LOGIC;
		aresetn			: in  STD_LOGIC;

		-- Master
		m_axis_tvalid	: out STD_LOGIC;
		m_axis_tdata	: out STD_LOGIC_VECTOR(23 downto 0);
		m_axis_tready	: in STD_LOGIC;
        m_axis_tlast    : out STD_LOGIC;

		-- Slave

		s_axis_tvalid	: in STD_LOGIC;
		s_axis_tdata	: in STD_LOGIC_VECTOR(23 downto 0);
        s_axis_tready	: out STD_LOGIC;
        s_axis_tlast    : in STD_LOGIC;

        --input
        volume          : in  STD_LOGIC_VECTOR(9 DOWNTO 0)

	);
end volume_controller;  

architecture Behavioral of volume_controller is

    constant SPAN             : integer     := 2 ** N_VALUE;
    constant SPAN_HALF        : integer     := SPAN / 2;
     
    
    signal volume_integer     : integer range -1300 to 1300  := 0;
    signal volume_temp        : integer range -1300 to 1300  := 0;
    signal DorM               : std_logic := '0'; -- 0 is division, 1 is multiplication
    signal m_axis_tlast_temp  : std_logic := '0';

    signal s_axis_tready_int  : std_logic := '1';
    signal m_axis_tvalid_int   : std_logic := '0';
    signal new_data           : std_logic := '0';


    signal counter_span       : integer range -1300 to 1300 := 0; 
    signal counter            : integer range -1300 to 1300 := 0;
    signal output_temp        : signed(23 downto 0) := (Others => '1');
    signal is_computing       : std_logic := '0';
    signal is_computing_counter :std_logic :='0';
	
begin

    s_axis_tready <= s_axis_tready_int;
    m_axis_tvalid <= m_axis_tvalid_int;
	
    volume_integer <= to_integer(unsigned(volume));

	process(aclk, aresetn)
    begin
        if aresetn = '0' then

            counter_span <= 0;
            counter <= 0;
            output_temp <= (others => '1');
            is_computing <= '0';
            is_computing_counter <= '0';
            s_axis_tready_int <='1';
            m_axis_tvalid_int <= '0';
            new_data <= '0';
            m_axis_tlast_temp <= '0';
            DorM <= '0';
            volume_integer <= 0;
            volume_temp <= 0;

        elsif rising_edge(aclk) then
           

            if s_axis_tready_int = '1' and s_axis_tvalid = '1' then

                m_axis_tlast_temp <= s_axis_tlast;
                output_temp <= signed(s_axis_tdata);


                volume_temp <= volume_integer - 512;

                if volume_temp > 0 then
                    DorM <= '1';
                else
                     DorM <= '0';
                end if;

                if DorM = '1' then

                    counter <= volume_temp + SPAN_HALF;
                    counter_span <= N_VALUE;

                    is_computing_counter <= '1';

                end if;

                if DorM = '0' then
  
                    counter <= -(volume_temp - SPAN_HALF);
                    counter_span <= N_VALUE;

                    is_computing_counter <= '1';
                        
                end if;

            end if;
            
             -- We use this series of ifs to divide N_value times volume_temp + Span_half to get the right counter of how many times we have to divide a channel below in "operations on volume"
            if is_computing_counter = '1' then

                s_axis_tready_int <= '0';

                if counter_span /= 0 then

                    counter <= counter /2;


                    counter_span <= counter_span - 1;
                end if;
                
                if counter_span = 0 then
                    
                    is_computing_counter <= '0';
                    is_computing <= '1';


                end if;
            end if;

            -- OPERATIONS ON VOLUME --
            if is_computing = '1' then

                s_axis_tready_int <= '0';

                if counter /= 0 then

                    if DorM = '1' then

                        if output_temp(output_temp'HIGH) = '1' and output_temp(output_temp'HIGH-1) = '0' then --overflow condition for negative number 
                            output_temp(output_temp'HIGH) <= '1'; 
                            output_temp(output_temp'HIGH-1 downto 0) <= (others => '0');
                            counter <= 0;
                        elsif output_temp(output_temp'HIGH) = '0' and output_temp(output_temp'HIGH-1) = '1' then --overflow condition for positive number
                            output_temp(output_temp'HIGH) <= '0'; 
                            output_temp(output_temp'HIGH-1 downto 0) <= (others => '1');
                            counter <= 0;
                        else 
                            output_temp <= output_temp(output_temp'HIGH-1 downto 0) & '0';
                        end if;
                        
                    end if;

                    if DorM = '0' then

                        output_temp <= output_temp(output_temp'HIGH) & output_temp(output_temp'HIGH downto 1);

                    end if;

                    counter <= counter - 1;
                end if;
                
                if counter = 0 then
                    
                    is_computing <= '0';
                    new_data <= '1';

                end if;
            end if;

            if is_computing_counter = '0' and is_computing = '0' then
                s_axis_tready_int <= '1';
            end if;

            --error resistance
            if counter < 0 then
                counter <= 0;
            end if;

            if counter_span < 0 then
                counter_span <= 0;
            end if;
            
            --master loading--
            if new_data = '1' and m_axis_tvalid_int = '0' then

                m_axis_tdata <= std_logic_vector(output_temp);
                m_axis_tvalid_int <= '1';
                m_axis_tlast <= m_axis_tlast_temp;
                new_data <= '0';

            end if;
            -- master handshake
            if m_axis_tready = '1' and m_axis_tvalid_int = '1' then
                m_axis_tvalid_int <= '0';
            end if;

        end if;

	end process;

	
end architecture;