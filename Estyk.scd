(
s.waitForBoot({
	{
		var showResetButton = false;
		
		var windSynth;
		var impulseSynth;
		var fmSynth;
		var masterSynth;
		var sampleGroup;
		var windBus = Bus.audio(s, 2);
		var impulseBus = Bus.audio(s, 2);
		var fmBus = Bus.audio(s, 2);
		var sampleBus = Bus.audio(s, 2);
		var scopeBuffer = Buffer.alloc(s, 1024, 2);
		var svgFolder, synthFree;
		
		var samples = [
			"pious.wav", "crac.wav",
			"marcheForet.wav", "eau.wav", "autoPiou.wav"
		];
		var buffers = Array.fill(samples.size, { nil });
		var sampleSynths = Array.fill(samples.size, { nil });
		var samplerUIStates;

		// Functions
		var mute, reset, quit;

		var defaultValues = (
			\windAmp: 0,
			\windFreq: 100,
			\impulseRate: 1,
			\impulseAmp: 0,
			\fmAmp: 0,
			\fmFreq: 100,
			\fmSpread: 0,
			\fmMul: 1,
			\fmModIndex: 0,
			\fmModFreq: 1,
			\samplerAmp: 0.5,
			\samplerRate: 1,
			\masterAmp: 0.5,
			\feedbackAmount: 0,
			\feedbackDelay: 0.05,
			\decAmount: 0,
			\decSRate: 48000,
			\decBitDepth: 24,
			\lfoRate: 1,
			\lfoAmount: 0,
			\reverbAmount: 0,
		);

		var fmFreq = defaultValues[\fmFreq];
		var fmMul = defaultValues[\fmMul];
		
		// GUI
		var win, defaultStyle, fullScreen;
		var windStyle, wind2DSlider, windView;
		var impulseStyle, impulse2DSlider, impulseView;
		var fmStyle, fmSmallStyle, fm2DSlider;
		var fmAmpSlider, fmAmpIMG;
		var fmFreqSlider, fmFreqIMG, fmSpreadSlider;
		var fmSpreadIMG, fmMulSelector, fmView;
		var sampleStyle, sampleAmpSlider, sampleIMG;
		var sampleRateSlider, samplerLayout;
		var samplerButtons, sampleView;
		var ampStyle, ampSlider, ampIMG, scopeView, ampView;
		var feedbackStyle, feedbackSlider;
		var decimatorStyle, decAmountSlider;
		var decAmountIMG, decSRateSlider;
		var decSRateIMG, decBitDepthSlider;
		var decBitDepthIMG, decimatorView;
		var lfoStyle, lfoSlider;
		var reverbStyle, reverbSlider, reverbIMG, reverbView;
		var masterView;
		var resetButton;
		
		// Set initial state
		svgFolder = thisProcess.nowExecutingPath.dirname +/+ "svg/";
		synthFree = false;
		fullScreen = false;
		
		// Load samples into buffers
		samples.do({ |fileName, index|
			buffers[index] = Buffer.read(
				s,
				thisProcess.nowExecutingPath.dirname +/+ "samples" +/+ fileName
			);
		});
		
		s.sync;

		sampleGroup = Group(
			s.defaultGroup.nodeID,
			\addToHead
		);

		// Load SynthDefs
		windSynth = SynthDef(\estykWind, { |out = 0, amp = 0, bpFreq = 100|
			var snd = [WhiteNoise.ar(amp), WhiteNoise.ar(amp)];
			snd = BPF.ar(snd, bpFreq);
			Out.ar(out, snd);
		}).play(s, [
			\amp, defaultValues[\windAmp],
			\bpFreq, defaultValues[\windFreq],
			\out, windBus
		]);

		impulseSynth = SynthDef(\estykImpulse, { |out = 0, amp = 0, rate = 1|
			var snd = Dust2.ar(rate, mul: amp)!2;
			Out.ar(out, snd);
		}).play(s, [
			\amp, defaultValues[\impulseAmp],
			\rate, defaultValues[\impulseRate],
			\out, impulseBus
		]);

		fmSynth = SynthDef(\estykFM, { |out = 0, amp = 0, freq = 100,
			spread = 0, modFreq = 1, modIndex = 0|
			var carrier, mod;
			freq = [freq * (1 - spread), freq * (1 + spread)];
			mod = SinOsc.ar(
				freq * modFreq,
				mul: modIndex);
			carrier = SinOsc.ar(
				freq,
				mul: amp / 2
			);
			carrier = LeakDC.ar(carrier);
			carrier = Mix.ar([
				carrier,
				SinOsc.ar(freq * mod, mul: amp / 2)
			]);
			carrier = carrier;
			Out.ar(out, carrier);
		}).play(s, [
			\amp, defaultValues[\fmAmp],
			\freq, defaultValues[\fmFreq] * defaultValues[\fmMul],
			\spread, defaultValues[\fmSpread],
			\modIndex, defaultValues[\fmModIndex],
			\modFreq, defaultValues[\fmModFreq],
			\out, fmBus
		]);

		SynthDef(\estykSampler, { |out = 0, amp = 0.5, gate = 0,
			bufnum, rate = 1|
			var snd = PlayBuf.ar(
				2,
				bufnum,
				BufRateScale.kr(bufnum) * rate,
				loop: 1
			);
			snd = snd * amp * Lag.kr(gate, 0.5);
			Out.ar(out, snd);
		}).add;

		masterSynth = SynthDef(\estykMaster, { |amp = 0.5,
			feedBackAmount = 0, feedBackDelay = 0,
			lfoAmount = 0, lfoRate = 1, reverbAmount = 0,
			decAmount = 0, decSRate = 48000, decBitDepth = 24,
			windIn, impulseIn, fmIn, sampleIn, scopeBuffer|

			var wind = In.ar(windIn, 2);
			var impulse = In.ar(impulseIn, 2);
			var fm = In.ar(fmIn, 2);
			var sample = In.ar(sampleIn, 2);

			var mix = Mix.ar([wind, impulse, fm, sample]);
			var feedBack = LocalIn.ar(2);

			var lfoControl, reverb, decimator;

			lfoControl = 1 - SinOsc.ar(lfoRate, 0, lfoAmount / 2, lfoAmount / 2);
			mix = mix * lfoControl;

			decimator = mix;
			decimator = Decimator.ar(decimator, decSRate, decBitDepth);
			decimator = decimator * decAmount;
			mix = mix * (1 - decAmount);
			mix = mix + decimator;

			mix = Mix.ar([mix, feedBack]);
			LocalOut.ar(
				DelayC.ar(
					mix,
					2,
					feedBackDelay,
					feedBackAmount
				)
			);

			reverb = mix;
			4.do({ reverb = AllpassC.ar(
				// Update max if needed
				reverb, 0.1, { Rand(0.001, 0.1) }.dup, 4) });
			reverb = reverb * reverbAmount;
			mix = mix * (1 - reverbAmount);
			mix = mix + reverb;

			mix = mix * amp;
			mix = Limiter.ar(mix, amp, 0.01);
			mix = LeakDC.ar(mix);

			Out.ar(0, mix);
			ScopeOut2.ar(mix, scopeBuffer);
		}).play(s, [
			\amp, defaultValues[\masterAmp],
			\feedBackAmount, defaultValues[\feedbackAmount],
			\feedBackDelay, defaultValues[\feedbackDelay],
			\lfoAmount, defaultValues[\lfoAmount],
			\lfoRate, defaultValues[\lfoRate],
			\reverbAmount, defaultValues[\reverbAmount],
			\decAmount, defaultValues[\masterAmp],
			\decSRate, defaultValues[\decSRate],
			\decBitDepth, defaultValues[\decBitDepth],
			\windIn, windBus,
			\impulseIn, impulseBus,
			\fmIn, fmBus,
			\sampleIn, sampleBus,
			\scopeBuffer, scopeBuffer
		], \addToTail);

		s.sync;

		// Play samples
		buffers.do({ |buffer, index|
			sampleSynths[index] = Synth(
				\estykSampler,
				[
					\rate, defaultValues[\samplerRate],
					\amp, defaultValues[\samplerAmp],
					\out, sampleBus,
					\bufnum, buffer
				],
				sampleGroup
			)
		});

		{
			//////////////
			//    UI    //
			//////////////
			win = Window(
				"Estyk",
				Rect(
					Window.screenBounds.width * 0.1,
					Window.screenBounds.height * 0.1,
					Window.screenBounds.width * 0.8,
					Window.screenBounds.height * 0.8
				);
			)
			.background_(Color.black);

			defaultStyle = GMStyle()
			.borderSize_(2)
			.secondBorderSize_(6)
			.thirdBorderSize_(0);

			////////////////
			//    WIND    //
			////////////////
			windStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.5, 0.5, 0.5))
			.borderColor_(Color(0, 0, 0))
			.secondBorderColor_(Color(1, 1, 1))
			.backColor_(Color(0.333, 0.333, 0.333))
			.secondBorderSize_(1);
			wind2DSlider = GMSymbol2DSlider()
			.min_([50, 0])
			.max_([3200, 1])
			.scales_([\exp, \lin])
			.values_([
				defaultValues[\windFreq],
				defaultValues[\windAmp]
			])
			.displayValues_(false)
			.style_(windStyle)
			.svg_(svgFolder +/+ "windBG.svg")
			.svgRatio_(1.05)
			.action_({ |x, y|
				windSynth.set(\bpFreq, x);
				windSynth.set(\amp, y);
			});
			windView = UserView()
			.layout_(
				VLayout()
				.margins_(0)
				.spacing_(0)
				.add(wind2DSlider, 9)
				.add(UserView().maxHeight_(16), 1)
			);
			
			///////////////////
			//    IMPULSE    //
			///////////////////
			impulseStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0, 0, 0))
			.borderColor_(Color.white)
			.secondBorderColor_(Color.black)
			.backColor_(Color.white)
			.backgroundColor_(Color.white);
			impulse2DSlider = GMSymbol2DSlider()
			.min_([0.05, 0])
			.max_([10000, 1])
			.scales_([\exp, \exp])
			.values_([
				defaultValues[\impulseRate],
				defaultValues[\impulseAmp]
			])
			.displayValues_(false)
			.style_(impulseStyle)
			.svg_(svgFolder +/+ "impulseBG.svg")
			.svgRatio_(1.4)
			.action_({ |x, y|
				impulseSynth.set(\rate, x);
				impulseSynth.set(\amp, y);
			});
			impulseView = UserView()
			.layout_(
				VLayout()
				.margins_(0)
				.spacing_(0)
				.add(UserView().maxHeight_(16), 1)
				.add(impulse2DSlider, 9)
			);

			//////////////
			//    FM    //
			//////////////
			fmStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.666, 0, 0.333))
			.selectedColor_(Color(0.666, 0, 0.333))
			.secondColor_(Color(0.666, 0, 0.333))
			.borderColor_(Color(0.333, 0, 0.123))
			.secondBorderColor_(Color(0.666, 0, 0.333))
			.backColor_(Color(0.5, 0, 0.2))
			.backgroundColor_(Color(0.25, 0, 0.1));
			fmSmallStyle = fmStyle
			.deepCopy
			.borderSize_(1)
			.secondBorderSize_(2)
			.thirdBorderSize_(0);
			fm2DSlider = GMSymbol2DSlider()
			.min_([0, 1/8])
			.max_([20, 1*8])
			.scales_([\lin, \lin])
			.values_([
				defaultValues[\fmModIndex],
				defaultValues[\fmModFreq]
			])
			.helpersNumbers_([2, 3])
			.helperSubdivisions_([9, 2])
			.displayHelpers_(true)
			.helpersStyle_(\dot)
			.displayValues_(false)
			.style_(fmStyle)
			.svg_(svgFolder ++ "fm.svg")
			.svgRatio_(0.75)
			.action_({ |x, y|
				fmSynth.set(\modIndex, x);
				fmSynth.set(\modFreq, y);
			});
			fmAmpSlider = GMFaderSlider()
			.style_(fmSmallStyle)
			.displayValue_(false)
			.value_(defaultValues[\fmAmp])
			.action_({ |value| fmSynth.set(\amp, value); });
			fmAmpIMG = GMButton()
			.svg_(svgFolder ++ "fmAmp.svg")
			.style_(fmSmallStyle);
			fmFreqSlider = GMSymbolSlider()
			.orientation_(\horizontal)
			.style_(fmSmallStyle)
			.min_(100)
			.max_(200)
			.value_(defaultValues[\fmFreq])
			.scale_(\exp)
			.displayValue_(false)
			.symbolRatio_(0.5)
			.action_({ |value|
				fmFreq = value;
				fmSynth.set(\freq, fmFreq * fmMul);
			});
			fmFreqIMG = GMButton()
			.svg_(svgFolder ++ "fmFreq.svg")
			.style_(fmSmallStyle);
			fmSpreadSlider = GMSymbolSlider()
			.orientation_(\horizontal)
			.symbol_(\diamond)
			.style_(fmSmallStyle)
			.min_(0)
			.max_(1)
			.value_(defaultValues[\fmSpread])
			.scale_(\exp)
			.displayValue_(false)
			.symbolRatio_(0.7)
			.action_({ |value| fmSynth.set(\spread, value); });
			fmSpreadIMG = GMButton()
			.svg_(svgFolder ++ "spread.svg")
			.style_(fmSmallStyle);
			fmMulSelector = GMMultiButton()
			.orientation_(\vertical)
			.style_(fmSmallStyle)
			.states_([
				(
					string: "", color: Color(0.5, 0, 0.2),
					fontColor: Color.black, svg: svgFolder ++ "x8.svg"
				),
				(
					string: "", color: Color(0.5, 0, 0.2),
					fontColor: Color.black, svg: svgFolder ++ "x4.svg"
				),
				(
					string: "", color: Color(0.5, 0, 0.2),
					fontColor: Color.black, svg: svgFolder ++ "x2.svg"
				),
				(
					string: "", color: Color(0.5, 0, 0.2),
					fontColor: Color.black, svg: svgFolder ++ "x1.svg"
				),
			])
			.state_([8, 4, 2, 1].indexOfEqual(defaultValues[\fmMul]))
			.action_({ |index|
				fmMul = [8, 4, 2, 1][index];
				fmSynth.set(\freq, fmFreq * fmMul);
			});
			fmView = UserView()
			.layout_(
				HLayout()
				.margins_(0)
				.spacing_(0)
				.add(UserView().maxWidth_(24), 1)
				.add(
					VLayout()
					.margins_(0)
					.spacing_(0)
					.add(
						HLayout()
						.margins_(0)
						.spacing_(0)
						.add(
							VLayout()
							.margins_(0)
							.spacing_(0)
							.add(fmAmpIMG, 1)
							.add(fmAmpSlider, 4),
							1
						)
						.add(fm2DSlider, 9)
						.add(fmMulSelector, 1),
						4
					)
					.add(
						HLayout()
						.margins_(0)
						.spacing_(0)
						.add(fmFreqIMG, 1)
						.add(fmFreqSlider, 9),
						1
					)
					.add(
						HLayout()
						.margins_(0)
						.spacing_(0)
						.add(fmSpreadIMG, 1)
						.add(fmSpreadSlider, 9),
						1
					),
					9
				)
				.add(UserView().maxWidth_(24), 1)
			);

			///////////////////
			//    SAMPLER    //
			///////////////////
			samplerUIStates = [
				[
					(color: Color(0, 0, 0.1), svg: svgFolder ++ "piouShut.svg"),
					(color: Color(0.2, 0.2, 0.5), svg: svgFolder ++ "piouOpen.svg")
				],
				[
					(color: Color(0, 0, 0.1), svg: svgFolder ++ "brancheShut.svg"),
					(color: Color(0.2, 0.2, 0.5), svg: svgFolder ++ "brancheOpen.svg")
				],
				[
					(color: Color(0, 0, 0.1), svg: svgFolder ++ "pasShut.svg"),
					(color: Color(0.2, 0.2, 0.5), svg: svgFolder ++ "pasOpen.svg")
				],
				[
					(color: Color(0, 0, 0.1), svg: svgFolder ++ "eauShut.svg"),
					(color: Color(0.2, 0.2, 0.5), svg: svgFolder ++ "eauOpen.svg")
				],
				[
					(color: Color(0, 0, 0.1), svg: svgFolder ++ "routeShut.svg"),
					(color: Color(0.2, 0.2, 0.5), svg: svgFolder ++ "routeOpen.svg")
				],
			];
			sampleStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.35, 0.35, 0.7))
			.selectedColor_(Color(0.8, 0.8, 1))
			.borderColor_(Color(0, 0, 0))
			.secondBorderColor_(Color(0.5, 0.5, 1))
			.backColor_(Color(0.3, 0.3, 0.6))
			.helpersColor_(Color(1, 1, 1, 0.5))
			.borderSize_(0)
			.secondBorderSize_(3);
			sampleAmpSlider = GMFaderSlider()
			.style_(sampleStyle)
			.displayValue_(false)
			.displayHelpers_(true)
			.helpersStyle_(\line)
			.helpersNumber_(3)
			.helperSubdivisions_(4)
			.helpersRatio_(0.25)
			.maxWidth_(128)
			.value_(defaultValues[\samplerAmp])
			.sliderRatio_(0.75)
			.action_({ |value| sampleGroup.set(\amp, value); });
			sampleIMG = GMButton()
			.svg_(svgFolder ++ "rec.svg")
			.maxWidth_(128)
			.style_(sampleStyle);
			sampleRateSlider = GMSymbolSlider()
			.orientation_(\horizontal)
			.style_(sampleStyle)
			.min_(8.reciprocal)
			.max_(8)
			.scale_(\exp)
			.value_(defaultValues[\samplerRate])
			.polarity_(\bi)
			.displayHelpers_(true)
			.helpersRatio_(0.4)
			.helpersNumber_(3)
			.helperSubdivisions_(2)
			.symbolRatio_(0.7)
			.displayValue_(false)
			.action_({ |value| sampleGroup.set(\rate, value); });
			samplerLayout = HLayout()
			.margins_(15)
			.spacing_(8);
			samplerButtons = List(0);
			sampleSynths.do({ |synth, index|
				var button = GMSwitchButton()
				.style_(sampleStyle)
				.states_(samplerUIStates[index])
				.svgRatio_(1)
				.action_({ |state| synth.set(\gate, state); });
				samplerLayout.add(button);
				samplerButtons.add(button);
			});
			sampleView = UserView()
			.layout_(
				VLayout()
				.margins_(0)
				.spacing_(0)
				.add(
					HLayout()
					.margins_(0)
					.spacing_(0)
					.add(sampleIMG, 1)
					.add(samplerLayout, 4)
					.add(sampleAmpSlider, 1),
					2
				)
				.add(sampleRateSlider, 1)
			);

			//////////////////
			//    MASTER    //
			//////////////////

			//    REVERB    //
			reverbStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.4, 0.8, 0.4))
			.borderColor_(Color(0.2, 0.5, 0.2))
			.secondBorderColor_(Color(0.2, 0.5, 0.2))
			.backColor_(Color(0.333, 0.666, 0.333))
			.borderSize_(2)
			.secondBorderSize_(0);
			reverbSlider = GMFaderSlider()
			.value_(defaultValues[\reverbAmount])
			.orientation_(\horizontal)
			.displayValue_(false)
			.style_(reverbStyle)
			.action_({ |value| masterSynth.set(\reverbAmount, value); });
			reverbIMG = GMButton()
			.svg_(svgFolder ++ "reverb.svg")
			.style_(reverbStyle);
			reverbView = HLayout()
			.margins_(5)
			.spacing_(0)
			.add(reverbIMG, 2)
			.add(reverbSlider, 8);

			//    DECIMATOR    //
			decimatorStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.9, 0.4, 0.2))
			.borderColor_(Color(0, 0, 0))
			.secondBorderColor_(Color(0.8, 0.4, 0.2))
			.backColor_(Color.black)
			.helpersColor_(Color(0, 0, 0, 0.5))
			.borderSize_(2)
			.secondBorderSize_(2);
			decAmountSlider = GMFaderSlider()
			.min_(0)
			.max_(1)
			.scale_(\log)
			.value_(defaultValues[\decAmount])
			.displayValue_(false)
			.sliderRatio_(0.666)
			.style_(decimatorStyle)
			.displayHelpers_(true)
			.helpersStyle_(\line)
			.helpersRatio_(1)
			.helpersNumber_(5)
			.maxWidth_(96)
			.action_({ |value| masterSynth.set(\decAmount, value); });
			decAmountIMG = GMButton()
			.svg_(svgFolder ++ "decAmount.svg")
			.svgRatio_(0.8)
			.maxWidth_(96)
			.style_(decimatorStyle);
			decSRateSlider = GMFaderSlider()
			.min_(375)
			.max_(48000)
			.scale_(\exp)
			.value_(defaultValues[\decSRate])
			.displayValue_(false)
			.sliderRatio_(0.666)
			.style_(decimatorStyle)
			.displayHelpers_(true)
			.helpersStyle_(\line)
			.helpersRatio_(1)
			.helpersNumber_(5)
			.maxWidth_(96)
			.action_({ |value| masterSynth.set(
				\decSRate, value.round(1.0).asInteger); });
			decSRateIMG = GMButton()
			.svg_(svgFolder ++ "decSRate.svg")
			.svgRatio_(0.8)
			.maxWidth_(96)
			.style_(decimatorStyle);
			decBitDepthSlider = GMFaderSlider()
			.min_(2)
			.max_(24)
			.scale_(\lin)
			.value_(defaultValues[\decBitDepth])
			.displayValue_(false)
			.sliderRatio_(0.666)
			.style_(decimatorStyle)
			.displayHelpers_(true)
			.helpersStyle_(\line)
			.helpersRatio_(1)
			.helpersNumber_(5)
			.maxWidth_(96)
			.action_({ |value| masterSynth.set(
				\decBitDepth, value.round(1.0).asInteger); });
			decBitDepthIMG = GMButton()
			.svgRatio_(0.9)
			.svg_(svgFolder ++ "decBitDepth.svg")
			.maxWidth_(96)
			.style_(decimatorStyle);
			decimatorView = HLayout()
			.margins_(0)
			.spacing_(0)
			.add(UserView(), 1)
			.add(
				UserView()
				.maxWidth_(96 * 3)
				.layout_(
					HLayout()
					.margins_(0)
					.spacing_(0)
					.add(
						VLayout()
						.margins_(0)
						.spacing_(0)
						.add(UserView().maxHeight_(32), 2)
						.add(
							VLayout()
							.margins_(0)
							.spacing_(0)
							.add(decAmountIMG, 2)
							.add(decAmountSlider, 8),
							18
						)
					)
					.add(
						VLayout()
						.margins_(0)
						.spacing_(0)
						.add(UserView().maxHeight_(16), 1)
						.add(
							VLayout()
							.margins_(0)
							.spacing_(0)
							.add(decSRateIMG, 2)
							.add(decSRateSlider, 8),
							18
						)
						.add(UserView().maxHeight_(16), 1)
					)
					.add(
						VLayout()
						.margins_(0)
						.spacing_(0)
						.add(
							VLayout()
							.margins_(0)
							.spacing_(0)
							.add(decBitDepthIMG, 2)
							.add(decBitDepthSlider, 8),
							18
						)
						.add(UserView().maxHeight_(32), 2)
					)
				), 9
			)
			.add(UserView(), 1);
			
			//    FEEDBACK    //
			feedbackStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0, 0, 0))
			.borderColor_(Color(0.5, 0.4, 0.1))
			.secondBorderColor_(Color(0, 0, 0))
			.backgroundColor_(Color(0.9, 0.8, 0.5))
			.borderSize_(4)
			.secondBorderSize_(2);
			feedbackSlider = GMSymbol2DSlider()
			.style_(feedbackStyle)
			.svg_(svgFolder ++ "clock.svg")
			.svgRatio_(1.0)
			.displayValues_(false)
			.symbol_(\diamond)
			.displayLine_(true)
			.scales_([8, 1])
			.min_([0.02, 0])
			.max_([2, 1])
			.values_([
				defaultValues[\feedbackDelay],
				defaultValues[\feedbackAmount]
			])
			.action_({ |x, y|
				masterSynth.set(\feedBackDelay, x);
				masterSynth.set(\feedBackAmount, y);
			});

			//    LFO    //
			lfoStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.9, 0.45, 0.45, 0.75))
			.borderColor_(Color(0.15, 0.225, 0.15))
			.secondBorderColor_(Color(0.25, 0.35, 0.25))
			.thirdBorderColor_(Color(0.15, 0.225, 0.15))
			.backColor_(Color(0.666, 0.666, 0.333))
			.borderSize_(2)
			.secondBorderSize_(4)
			.thirdBorderSize_(2)
			.outlineSize_(0);
			lfoSlider = GMSymbol2DSlider()
			.style_(lfoStyle)
			.svg_(svgFolder ++ "lfo.svg")
			.svgRatio_(0.75)
			.displayValues_(false)
			.scales_([\exp, \log])
			.symbolRatio_(0.15)
			.symbolMinSize_(5)
			.min_([16.reciprocal, 0])
			.max_([16, 1])
			.values_([
				defaultValues[\lfoRate],
				defaultValues[\lfoAmount]
			])
			.action_({ |x, y|
				masterSynth.set(\lfoRate, x);
				masterSynth.set(\lfoAmount, y);
			});

			//    AMP    //
			ampStyle = defaultStyle
			.deepCopy
			.mainColor_(Color(0.8, 0.2, 0.2))
			.borderColor_(Color(0.333, 0, 0))
			.secondBorderColor_(Color(0.444, 0, 0))
			.thirdBorderColor_(Color(0.555, 0, 0))
			.backColor_(Color(0.888, 0.5, 0.5))
			.borderSize_(1)
			.secondBorderSize_(1)
			.thirdBorderSize_(1);
			ampSlider = GMFaderSlider()
			.min_(0)
			.max_(1)
			.scale_(\lin)
			.value_(defaultValues[\masterAmp])
			.displayValue_(false)
			.style_(ampStyle)
			.action_({ |value| masterSynth.set(\amp, value); });
			ampIMG = GMButton()
			.svg_(svgFolder ++ "masterAmp.svg")
			.style_(ampStyle);
			scopeView = ScopeView()
			.server_(s)
			.bufnum_(scopeBuffer.bufnum)
			.style_(1)
			.waveColors_(
				Color(
					ampStyle.mainColor.red,
					ampStyle.mainColor.green,
					ampStyle.mainColor.blue,
					0.5
				)!2
			)
			.start;
			ampView = HLayout()
			.spacing_(0)
			.margins_(0)
			.add(scopeView, 3)
			.add(
				VLayout()
				.margins_(0)
				.spacing_(0)
				.add(ampIMG, 2)
				.add(ampSlider, 8),
				1
			);

			masterView = UserView()
			.layout_(
				VLayout()
				.margins_(0)
				.spacing_(15)
				.add(reverbView, 1)
				.add(decimatorView, 2)
				.add(feedbackSlider, 2)
				.add(lfoSlider, 2)
				.add(ampView, 3)
			);

			// RESET BUTTON //
			if(showResetButton) {
				resetButton = GMFeedbackButton()
				.string_("reset")
				.style_(
					GMStyle()
					.borderColor_(Color.grey)
					.secondBorderColor_(Color.black)
					.backColor_(Color.black)
					.fontColor_(Color.grey)
					.borderSize_(2)
					.secondBorderSize_(2)
					.thirdBorderSize_(0)
				)
				.maxHeight_(48)
				.maxWidth_(256)
				.action_({ reset.value; });
				masterView.layout.insert(
					HLayout()
					.spacing_(0)
					.margins_(0)
					.add(resetButton),
					0,
					1
				);
			};

			reset = {
				// Synths update
				windSynth.set(\bpFreq, defaultValues[\windFreq]);
				windSynth.set(\amp, defaultValues[\windAmp]);
				impulseSynth.set(\rate, defaultValues[\impulseRate]);
				impulseSynth.set(\amp, defaultValues[\impulseAmp]);
				fmSynth.set(\modIndex, defaultValues[\fmModIndex]);
				fmSynth.set(\modFreq, defaultValues[\fmModFreq]);				
				fmSynth.set(\amp, defaultValues[\fmAmp]);
				fmFreq = defaultValues[\fmFreq];
				fmMul = defaultValues[\fmMul];
				fmSynth.set(\freq, fmFreq * fmMul);
				fmSynth.set(\spread, defaultValues[\fmSpread]);
				sampleGroup.set(\amp, defaultValues[\samplerAmp]);
				sampleGroup.set(\rate, defaultValues[\samplerRate]);
				sampleGroup.set(\gate, 0);
				masterSynth.set(\feedBackDelay, defaultValues[\feedbackAmount]);
				masterSynth.set(\feedBackAmount, defaultValues[\feedbackDelay]);
				masterSynth.set(\decAmount, defaultValues[\decAmount]);
				masterSynth.set(\decSRate, defaultValues[\decSRate]);
				masterSynth.set(\decBitDepth, defaultValues[\decBitDepth]);
				masterSynth.set(\lfoRate, defaultValues[\lfoRate]);
				masterSynth.set(\lfoAmount, defaultValues[\lfoAmount]);
				masterSynth.set(\reverbAmount, defaultValues[\reverbAmount]);
				masterSynth.set(\amp, defaultValues[\masterAmp]);

				// UI update
				wind2DSlider.values_([
					defaultValues[\windFreq],
					defaultValues[\windAmp]
				]);
				impulse2DSlider.values_([
					defaultValues[\impulseRate],
					defaultValues[\impulseAmp]
				]);
				fm2DSlider.values_([
					defaultValues[\fmModIndex],
					defaultValues[\fmModFreq]
				]);
				fmAmpSlider.value_(defaultValues[\fmAmp]);
				fmFreqSlider.value_(defaultValues[\fmFreq]);
				fmSpreadSlider.value_(defaultValues[\fmSpread]);
				fmMulSelector.state_([8, 4, 2, 1].indexOfEqual(defaultValues[\fmMul]));
				sampleAmpSlider.value_(defaultValues[\samplerAmp]);
				sampleRateSlider.value_(defaultValues[\samplerRate]);
				samplerButtons.do({ |button| button.state_(0); });
				feedbackSlider.values_([
					defaultValues[\feedbackDelay],
					defaultValues[\feedbackAmount]
				]);
				decAmountSlider.value_(defaultValues[\decAmount]);
				decSRateSlider.value_(defaultValues[\decSRate]);
				decBitDepthSlider.value_(defaultValues[\decBitDepth]);
				lfoSlider.values_([
					defaultValues[\lfoRate],
					defaultValues[\lfoAmount]
				]);
				reverbSlider.value_(defaultValues[\reverbAmount]);
				ampSlider.value_(defaultValues[\masterAmp]);
			};
			
			mute = {
				masterSynth.set(\amp, 0);
				ampSlider.value_(0);
			};
			
			quit = {
				scopeBuffer.free;
				if(synthFree.not) {
					windBus.free;
					impulseBus.free;
					fmBus.free;
					sampleBus.free;
					s.freeAll;
				};
			};

			win.onClose_({
				quit.value;
			});

			CmdPeriod.doOnce({
				synthFree = true;
				win.close;
			});

			View.globalKeyDownAction_({ |view, char, mod, unicode|
				// CTRL + F
				if(unicode == 6) {
					if(fullScreen)
					{ win.endFullScreen; }
					{ win.fullScreen; };
					fullScreen = fullScreen.not;
				};
				// ESC
				if(unicode == 27) { win.close; };
				// CHAR KEYS
				if(char == $m) { mute.value; };
				if(char == $r) { reset.value; };
			});

			win.layout_(
				HLayout()
				.margins_(20)
				.spacing_(20)
				.add(
					VLayout()
					.margins_(0)
					.spacing_(30)
					.add(
						HLayout()
						.margins_(0)
						.spacing_(20)
						.add(windView, 1)
						.add(impulseView, 1),
						2
					)
					.add(fmView, 3)
					.add(sampleView, 2),
					4
				)
				.add(masterView, 1)
			);

			win.front;

		}.defer;
	}.fork;
});
)