% Originally written by Michael Arsenault
% May 2012
% Embry-Riddle Aeronautical University
% Dr. Aroh Barjatya
function varargout = BoomSpinTest(varargin)
	% Begin initialization code - DO NOT EDIT
	gui_Singleton = 1;
	gui_State = struct('gui_Name', mfilename, ...
	'gui_Singleton', gui_Singleton, ...
	'gui_OpeningFcn', @BoomSpinTest_OpeningFcn, ...
	'gui_OutputFcn', @BoomSpinTest_OutputFcn, ...
	'gui_LayoutFcn', [] , ...
	'gui_Callback', []);
	
	if nargin && ischar(varargin{1})
		gui_State.gui_Callback = str2func(varargin{1});
	end
	if nargout
		[varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
	else
		gui_mainfcn(gui_State, varargin{:});
	end
	
	% End initialization code - DO NOT EDIT
	% --- Executes just before BoomSpinTest is made visible.
function BoomSpinTest_OpeningFcn(hObject, eventdata, handles, varargin)
	handles.output = hObject;
	guidata(hObject, handles);
	clc;
	set(gcf,'CloseRequestFcn',@my_closefcn);
	priorPorts = instrfind; % finds any existing Serial Ports in MATLAB
	delete(priorPorts); % and deletes them
	% NOTE: The port on your computer may be different than COM3.
	
	global port % MUST be global so that it can be closed by other functions!
port = serial('COM3');
fopen(port);
set(handles.motorTest, 'Enable', 'inactive');
set(handles.rpmUp, 'Enable', 'inactive');
set(handles.rpmDown, 'Enable', 'inactive');
set(handles.motorTest, 'ButtonDownFcn', {@motorTest_ButtonDownFcn, handles});
set(handles.rpmUp, 'ButtonDownFcn', {@rpmUp_ButtonDownFcn, handles});
set(handles.rpmDown, 'ButtonDownFcn', {@rpmDown_ButtonDownFcn, handles});
global rpmSet % Value that the user sets the RPM to (desired RPM)
global running % If running, 1. If not running, 0.
global motorTesting % If doing a motor test, 1. If not testing, 0.
global rpmHolder % Hold the value of the previous rpmSet. May not be needed?
global time % Array of times to use for plotting
global timeMax % timeMax is the x-axis range. Doubles when the current timeMax is reached.
global rpmVals % Array of RPM values
global ran % If the test stand has been run and not reset (may still be, may be stopped).
global cutting % If currently cutting
global cutTime % The start and end times for cutting. Always an even number of values.
rpmSet = 2.5;
rpmHolder = rpmSet;
running = 0;
ran = 0;
timeMax = 1; % One minute
motorTesting = 0;
time = [];
rpmVals = [];
cutting = 0;
cutTime = [];
34
% Set up RPM plot
axes(handles.rpmPlot);

 title('Spin Frequency');
 xlabel('Time (min)');
 xlim([0 1]);
 ylabel('Freq (Hz)');
 ylim([0 7]);
% --- Outputs from this function are returned to the command line.
function varargout = BoomSpinTest_OutputFcn(hObject, eventdata, handles)
% Get default command line output from handles structure
varargout{1} = handles.output;
% --- Executes on button press in startStop.
function startStop_Callback(hObject, eventdata, handles)
global running
global ran
global time
global rpmVals
global timeMax
global rpmSet
global cutting
global cutTime
global port
if(running == 0) % If not already running

 running = 1;
 % Aesthetics
 set(hObject, 'BackgroundColor', 'red');
 set(hObject, 'String', 'Stop');
 set(handles.cutWire, 'Enable', 'on');
 set(handles.motorTest, 'Enable', 'off');
 set(handles.save, 'Enable', 'off');
 set(handles.reset, 'Enable', 'off');

 if(length(time) > 0) % If a previous run has been done
 i = length(time) + 1;
 else
 i = 1;
 end

 speed = 75; %Start at 75 - near the lower range of possible speeds for the motor
 fwrite(port, speed); % Send command to the micro controller
 pause(3.5); % Pause and wait for the motor to spin up
 a = tic; % Reference point for times.

 while(running)

 data = fscanf(port); % Data is a tab-delimited string of info sent from the micro controller to
matlab

 if(~isempty(data)) % If data not empty, parse it
 vars = textscan(data, '%s%d\n\r', 'delimiter', '\t');
 [str1, num1] = deal(vars{:});
 else
 fprintf('Empty\n');
 end

 % The RPM value sent by the micro controller is for 1/3 of a
 % rotation and is in milliseconds. The total RPM (in Hz) is equal to the
 % following...
 RPM = 1/((double(num1)*3)/1000);
 rpmVals(i) = RPM;

 t = toc(a); % Current time of the previously calculated RPM

 pause(.01); % Pause MUST be included, otherwise interupts not possible (cannot hit "stop"button)

 if(i == 1)
 time(i) = 0;
 else
 time(i) = t/60; % Convert the time to minutes
 end

 % A simplified control of the speed. If too slow, speed up. If
 % too fast, slow down. Not perfect, but works well enough.
 if((RPM < rpmSet) && (speed <= 127))
 speed = speed + 0.05;
 fwrite(port, speed);
 elseif((RPM > rpmSet) && (speed > 69)) % 69 is about as slow as it can go
 speed = speed - 0.05;
 fwrite(port, speed);
 end

 % When the "Cut" button it pressed, turn on pin D6 for 2.5 seconds
 if(cutting == 1) % Cutting = 1 when "Cut" button pressed
 if(mod(length(cutTime),2) == 0)
 cutTime(length(cutTime)+1) = time(i);
fwrite(port, 128); % Pin D6 on
 set(handles.cutWire, 'Enable', 'off');
 end

 if(time(i)-cutTime(length(cutTime)) >= 2.5/60) % 2.5 seconds
 fwrite(port, 129); % Pin D6 off
 cutTime(length(cutTime)+1) = time(i);
 cutting = 0;
 set(handles.cutWire, 'Enable', 'on');
 end
 end

 % Plot the RPM and Cutting vs. Time
 axes(handles.rpmPlot);

 cla
 hold all
 p1 = plot(time, rpmVals, 'b');
 set(p1, 'LineWidth', 2);
 if(length(cutTime)>0)
 for j=1:length(cutTime)
 p2 = plot([cutTime(j) cutTime(j)], [0 10], ':r');
set(p2, 'LineWidth', 1);
 end
 end

 title('Spin Frequency');
 xlabel('Time (min)');
 ylabel('Freq (Hz)');

 if(time(i) >= timeMax)
 timeMax = 2*timeMax;
 end

 xlim([0 timeMax]);
 ylim([0 7]);%set yaxis range

 % Print the current RPM value in Hz
 if(running == 1)
 rpmString = sprintf('%.1f Hz', rpmVals(i));
 else
 rpmString = sprintf('0.0 Hz');
 fwrite(port, 0);
 end
 set(handles.realRPM, 'String', rpmString);

 i = i+1;
 end

 ran = 1;
else % If currently running
 running = 0;

 fwrite(port, 0); % Set motor speed to 0 (not spinning)
 % Aesthetics
 set(hObject, 'BackgroundColor', 'green');
 set(hObject, 'String', 'Start');
 set(handles.cutWire, 'Enable', 'off');
36
 set(handles.motorTest, 'Enable', 'inactive');
 set(handles.save, 'Enable', 'on');
 set(handles.reset, 'Enable', 'on');
end
% --- Executes on button press in save.
% Saves the most recent run to a text file (can be imported into excel and
% plotted)
function save_Callback(hObject, eventdata, handles)
global running
global ran
global time
global rpmVals
global cutTime
if(running == 0 && ran == 1)
 set(hObject, 'Enable', 'off');

 t = num2str(floor(now*10000)); % Completely unique string based on current time (date and time)
 file = strcat(t, '.txt'); % File to be written

 fileID = fopen(file,'w');
 % Report the cut times
 if(length(cutTime)>0)
 for j=1:2:length(cutTime)
 fprintf(fileID, 'Cut from %.5f to %.5f\r\n', cutTime(j), cutTime(j+1));
 end
 end

 % Print the RPM (Hz) and Times (sec)
 fprintf(fileID, 'Time\t\tFreq\r\n');
 for i=1:length(time)
 fprintf(fileID, '%.5f\t\t%.1f\r\n', time(i), rpmVals(i));
 end
 fclose(fileID);

end
% --- Executes on button press in reset.
% Resets everything back to original values (empties arrays, clears plot,
% etc)
function reset_Callback(hObject, eventdata, handles)
global running
global rpmSet
global time
global rpmVals
global timeMax
global rpmHolder
global cutTime
if(running == 0)
 set(handles.save, 'Enable', 'off');

 rpmSet = 2.5;
 rpmHolder = 2.5;
 time = [];
 timeMax = 1;
 rpmVals = [];
 cutTime = [];

 rpmString = sprintf('%.1f Hz (%.0f RPM)', rpmSet, rpmSet*60);
 set(handles.rpmSetValue,'String',rpmString)

 cla(handles.rpmPlot);
 axes(handles.rpmPlot);
 xlim([0 timeMax]);
 ylim([0 7]);%set yaxis range
end
% --- Executes on button press in cutWire.
function cutWire_Callback(hObject, eventdata, handles)
global cutting
cutting = 1;
37
% --- Executes on button press in motorTest.
function motorTest_Callback(hObject, eventdata, handles)
% ButtonDownFcn allows the user to hold the button down and not have to
% click it repeatedly
% Holding the "Motor Test" button will spin the motor at a speed of 74,
% near the lower end of possible speeds. This is not for conducting tests,
% but to ensure the motor is working properly and the test is properly set
% up on the stand
function motorTest_ButtonDownFcn(hObject, eventdata, handles)
global running
global motorTesting
global port
if(running == 0)
 set(hObject, 'Value', 1);
 if(motorTesting == 0)
 motorTesting = 1;
 fwrite(port, 74)
 end
end
% --- Executes on button press in rpmDown.
function rpmDown_Callback(hObject, eventdata, handles)
% ButtonDownFcn allows the user to hold the button down and not have to
% click it repeatedly
% Set the RPM to a lower value
function rpmDown_ButtonDownFcn(hObject, eventdata, handles)
global rpmSet
set(hObject, 'Value', 1);
while(get(hObject, 'Value') == 1)
 rpmSet = rpmSet - 0.1;
 if(rpmSet<0)
 rpmSet = 0; % Cannot have a negative RPM
 end
 % Print the new RPM value
 rpmString = sprintf('%.1f Hz (%.0f RPM)', rpmSet, rpmSet*60);
 set(handles.rpmSetValue,'String',rpmString);

 pause(0.1);
end
% --- Executes on button press in rpmUp.
function rpmUp_Callback(hObject, eventdata, handles)
% ButtonDownFcn allows the user to hold the button down and not have to
% click it repeatedly
% Set the RPM to a higher value
function rpmUp_ButtonDownFcn(hObject, eventdata, handles)
global rpmSet
set(hObject, 'Value', 1);
while(get(hObject, 'Value') == 1)

 rpmSet = rpmSet + 0.1;
 if(rpmSet>7)
 rpmSet = 7; % Max rpm of 7 (the original motor can only do 6.9 max)
 end
 % Print the new RPM value
 rpmString = sprintf('%.1f Hz (%.0f RPM)', rpmSet, rpmSet*60);
 set(handles.rpmSetValue,'String', rpmString);

 pause(0.1);
end
% If any of the "button down" buttons is released
function figure1_WindowButtonUpFcn(hObject, eventdata, handles)
38
global motorTesting
global rpmSet
global rpmHolder
global port
if(motorTesting == 1) % If the motor was testing, stop it
 motorTesting = 0;
 fwrite(port, uint8(0))
 set(handles.motorTest, 'Value', 0); % Appearance of the button to unpressed
else
 set(handles.rpmUp, 'Value', 0); % Appearance of the button to unpressed
 set(handles.rpmDown, 'Value', 0); % Appearance of the button to unpressed

 if(rpmSet ~= rpmHolder)
 rpmHolder = rpmSet;
 end
end
% This function is called when closing the GUI. The motor is stopped
% (speed of 0) and the port is closed.
function my_closefcn(hObject, eventdata, handles)
global port
fprintf('Goodbye\n');
fwrite(port, 0)
fclose(port)
close force
% --- Executes on mouse press over figure background.
% Does nothing. Cannot delete or errors with the compiling.
function figure1_ButtonDownFcn(hObject, eventdata, handles)