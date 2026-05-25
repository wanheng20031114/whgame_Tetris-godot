const translations = {
  "zh-CN": {
    "page_title": "俄罗斯方块学习与复盘系统 | 中文核心文档",
    "nav_foreword": "前言",
    "nav_intro": "引言",
    "nav_origin": "起因",
    "nav_rules": "对战规则",
    "nav_journey": "玩家路径",
    "nav_guidebook": "Guidebook",
    "nav_replay": "Replay",
    "nav_architecture": "架构",
    "nav_tech": "技术",
    "brand_title": "俄罗斯方块学习系统",
    "cover_author": "by wanheng",
    "cover_github": "GitHub",
    "cover_download": "下载",
    "cover_label": "中文核心文档",
    "cover_h1": "从俄罗斯方块的竞技性出发，设计一个帮助玩家变强的学习与复盘系统。",
    "cover_lead": "俄罗斯方块并不只是把方块排满一行再消掉。在对战中，玩家需要兼顾进攻与防守、提前规划落点、在高速下做出判断，还要通过赛后复盘不断修正自己的打法——这些要素共同构成了一套持续对抗的竞技体系。这个项目围绕“玩家如何从入门走向进阶”展开，重点讨论学习系统、复盘分析与整体技术结构。",
    "cover_flow_1_title": "前言",
    "cover_flow_1_desc": "先用普通语言说明俄罗斯方块为什么具有竞技性。",
    "cover_flow_2_title": "起因",
    "cover_flow_2_desc": "玩家想提升水平、击败更强对手，却缺少足够好用的辅助工具。",
    "cover_flow_3_title": "设计",
    "cover_flow_3_desc": "通过 Guidebook 与 Replay，分别解决“怎么学”和“哪里错”。",
    "cover_flow_4_title": "结构",
    "cover_flow_4_desc": "最后说明游戏、数据采集、AI 分析、多人对战和工具链如何组合。",
    "intro_kicker": "引言：先理解俄罗斯方块",
    "intro_h2": "俄罗斯方块不只是“把方块排满一行再消掉”。",
    "intro_p1": "很多人第一次想到俄罗斯方块时，脑中出现的是一个很简单的画面：方块从上往下落，玩家把它们排整齐，凑满一行就消掉。如果只看这一层，它确实像一个单人益智游戏。但俄罗斯方块，尤其是对战型俄罗斯方块，已经发展成了很接近电子竞技的系统。",
    "intro_p2": "在对战中，玩家并不是单纯追求“活得久”。每一次消行都可能转化成对对手的攻击。对手收到攻击后，棋盘下方会出现垃圾行，场地被不断向上推高。谁能更快地制造压力，谁能更稳定地处理压力，谁就更接近胜利。",
    "intro_p3": "正因如此，认真打俄罗斯方块和训练一项竞技项目并没有本质区别。玩家不仅要练操作速度，还要理解攻击效率、堆叠结构、预览判断、Hold 的使用、T-Spin、Combo、Back-to-Back 等概念。这些要素相互交织，形成了一套既有学习曲线、也有策略深度，同时值得反复复盘的竞技体系。",
    "intro_aside_h3": "面向完全不了解俄罗斯方块的读者",
    "intro_aside_p": "对战俄罗斯方块的重点不只是消行，而是把消行转化为压力，再把压力施加给对手。玩家既要制造攻击，也要处理自己收到的攻击。",
    "intro_fig1": "受到攻击时，压力会先显示在攻击条中，玩家还有机会通过自己的消行去抵消。",
    "intro_fig2": "如果压力没有被处理，攻击会转化为棋盘底部的垃圾行，直接改变接下来的局面。",
    "intro_footnote": "这两张 1v1 图展示了基本机制：攻击不会凭空出现，它先作为压力显示出来；如果玩家没有通过自己的消行抵消，压力就会进入棋盘，变成必须处理的垃圾行。",
    "origin_kicker": "项目起因",
    "origin_h2": "想要变强的玩家，往往缺少能直接帮助自己进步的工具。",
    "origin_p1": "玩家接触俄罗斯方块后，很快会产生一个自然目标：不仅要能稳定生存，还要能在对战中击败更多、更强的对手。这个目标会推动玩家继续学习攻击方式、堆叠方法、T-Spin、Combo，以及如何在压力下保持局面稳定。",
    "origin_p2": "现有资料中确实存在俄罗斯方块百科、视频教程和社区讨论，但这些内容通常更像资料库。它们能解释概念，却不一定能让玩家马上进入一个固定局面亲自尝试；也能展示高手操作，却不一定能指出普通玩家在自己对局中具体哪一步出现问题。",
    "origin_p3": "因此，系统设计的起点不是再增加一个普通模式，而是补上两类学习工具：一个负责把知识和操作连接起来，一个负责把玩家自己的对局拆开分析。前者是 Guidebook，后者是 Replay。",
    "origin_aside_h3": "设计起点",
    "origin_aside_p": "玩家真正需要的是可操作的学习环境和可回看的错误分析。只阅读概念不够，只反复游玩也不一定能发现问题。",
    "rules_kicker": "对战规则的最小解释",
    "rules_h2": "要理解这个项目，先要知道“消行为什么会变成攻击”。",
    "rules_p1": "在普通印象里，消一行只是得分。但在对战俄罗斯方块里，消行同时也是一种攻击行为。消得越有价值，给对手制造的压力越大。例如一次消四行，也就是 Tetris，通常比零散地消一两行更有攻击价值。",
    "rules_p2": "更进一步，T-Spin Double 这类技巧虽然只消两行，却因为操作难度和结构要求更高，在很多现代规则中能产生接近甚至等同于 Tetris 的攻击力。这就是为什么进阶玩家会主动学习 T-Spin：它不是炫技，而是更高效率地把有限方块转化为攻击。",
    "rules_p3": "同时，玩家还可以看到接下来 5 个方块，并可以把一个方块暂存在 Hold 中。这让俄罗斯方块不再只是反应游戏，也像棋类游戏一样，需要提前规划几步之后的局面。",
    "rules_stack_1_title": "棋盘",
    "rules_stack_1_desc": "标准场地是 10 列 × 20 行。越接近顶部，死亡风险越高。",
    "rules_stack_2_title": "Next 5 + Hold",
    "rules_stack_2_desc": "玩家能看到后续 5 个方块，并能暂存 1 个方块，因此每一步都带有规划性质。",
    "rules_stack_3_title": "攻击与垃圾行",
    "rules_stack_3_desc": "高价值消行会给对手发送垃圾行。垃圾行会抬高场地，压缩可操作空间。",
    "rules_stack_4_title": "抵消",
    "rules_stack_4_desc": "自己即将受到攻击时，可以通过消行抵消部分压力，而不是只能被动承受。",
    "journey_kicker": "从玩家需求逆推系统",
    "journey_h2": "系统不是先列功能，而是先整理玩家会怎样一步步想变强。",
    "journey_step1_h3": "首先，玩家需要知道自己在玩什么。",
    "journey_step1_p": "新手最先需要的不是复杂技巧，而是基础知识：棋盘结构、方块种类、Hold、Next、消行、攻击、垃圾行，以及为什么有些消除方式更有价值。",
    "journey_step2_h3": "然后，玩家需要一个人安全地练习。",
    "journey_step2_p": "单人 Marathon 模式承担这个任务。玩家可以不被对手干扰，先熟悉操作、堆叠、消行节奏和游戏速度。这个阶段解决的是“能不能稳定玩下去”。",
    "journey_step3_h3": "接着，玩家会开始思考怎样才能打得更好。",
    "journey_step3_p": "这时需要 Guidebook。它负责解释 Wall Kick、Combo、T-Spin 等技巧背后的原理，并通过模拟演练让玩家在预设棋盘中实际操作一次。",
    "journey_step4_h3": "再往后，玩家会想知道自己哪里错了。",
    "journey_step4_p": "单纯多玩可能重复同样的问题。Replay 系统将对局拆解，帮助玩家快速发现低质量操作，并通过 AI 推荐路线指导后续练习。",
    "journey_step5_h3": "最后，玩家需要确认自己的进步。",
    "journey_step5_p": "玩家可以通过长期数据、雷达图和对战结果确认成长。进步有时很小，体感不明显，但数据可以把这种变化留下来。",
    "guide_kicker": "Guidebook：从“知道概念”到“亲手做过”",
    "guide_h2": "教程不应该只停留在文字和视频里。",
    "guide_p1": "很多玩家看过 T-Spin 或 Combo 的视频，但真正回到游戏里时，仍然不知道该怎样构造局面。原因很简单：俄罗斯方块的技巧不是只靠“看懂”就能掌握的，玩家必须在真实棋盘上完成移动、旋转、下落和消除，才能理解这个技巧为什么成立。",
    "guide_p2": "所以 Guidebook 的设计不是传统说明书，而是一个学习入口。它先用普通语言解释技巧，再给出必要的背景知识和操作顺序，最后让玩家进入模拟演练。在模拟演练里，棋盘、当前方块、目标和成功条件都是固定的，玩家只需要聚焦在这一个知识点上。",
    "guide_p3": "这样做的目的，是把学习压力拆小。玩家不需要在完整对局里碰运气等到合适局面，也不需要一边被对手攻击一边学习新技巧。他可以在一个可控场景中，先把核心动作做对一次。",
    "guide_module_1_title": "基础知识",
    "guide_module_1_desc": "攻击力、垃圾行、抵消、B2B、Combo 等规则先讲清楚。",
    "guide_module_2_title": "操作章节",
    "guide_module_2_desc": "Wall Kick、Combo、T-Spin Double 等内容拆成可学习的小章节。",
    "guide_module_3_title": "模拟演练",
    "guide_module_3_desc": "玩家进入固定局面，用真实操作完成一次目标动作。",
    "guide_module_4_title": "反馈",
    "guide_module_4_desc": "系统判断是否完成目标，让玩家知道动作是否真正成立。",
    "replay_kicker": "Replay：把“感觉打得还行”变成可观察的数据",
    "replay_h2": "AI 分析更适合放在对局之后，而不是直接插入对局之中。",
    "replay_p1": "如果 AI 在对局中不断提示玩家应该怎么放，短期看起来很方便，但它可能会干扰玩家自己的判断。玩家会变成跟随提示操作，而不是建立自己的局面理解。俄罗斯方块的核心乐趣之一，正是玩家在压力中独立做出选择。",
    "replay_p2": "因此，AI 的主要作用被放在对局之后。玩家先完整打一局，保留原本的游戏体验；结束后再进入 Replay，像看比赛录像一样查看自己每一步的选择。这样 AI 不替玩家玩，而是在游戏外帮助玩家理解自己。",
    "replay_p3": "Replay 首先给出逐步评分。玩家可以快速定位一局中损失较大的操作。找到问题后，玩家自然会问：那这一步有没有更好的放法？于是系统显示 AI 推荐的下落位置，并给出接下来数步的路线参考。它不是一句抽象建议，而是直接把“更好的选择”放到棋盘上。",
    "replay_p4": "另一方面，玩家也需要知道整局表现如何。左侧数据面板统计一局的整体表现，雷达图则把速度、攻击、效率、结构、稳定性、视野等维度可视化。当玩家一段时间后再次比较这些数据，就能看到自己一点点变强的证据。",
    "replay_aside_h3": "Replay 的设计原则",
    "replay_aside_p": "AI 不应该抢走玩家的操作权。它更像赛后的教练：先让玩家完成比赛，再指出问题、展示参考答案，并把进步记录下来。",
    "replay_fig1_cap": "Replay 界面把棋盘、时间线、AI 推荐和解释面板放在一起，帮助玩家逐步检查自己的选择。",
    "replay_fig2_cap": "单局概要数据让玩家知道这一局整体表现如何。",
    "replay_fig3_cap": "雷达图把不同能力维度压缩成一个容易比较的形状。",
    "replay_note_h3": "从一局到长期变化",
    "replay_note_p": "单局概要回答“这一局发生了什么”，雷达图回答“能力结构有什么特点”。当玩家反复复盘，就能把每一局的经验连接成长期进步。",
    "arch_kicker": "项目结构",
    "arch_h2": "整个系统围绕玩家成长闭环组织，而不是把功能简单堆在一起。",
    "arch_title_entry": "大厅入口",
    "arch_entry_1": "单人练习",
    "arch_entry_2": "知识与模拟演练",
    "arch_entry_3": "赛后分析",
    "arch_entry_4": "1v1 / 多人对战",
    "arch_connector": "玩家在不同模式之间循环：练习 → 学习 → 复盘 → 对战 → 再练习",
    "arch_layer_1_title": "游戏运行层",
    "arch_layer_1_i1": "10 × 20 棋盘",
    "arch_layer_1_i2": "SRS 旋转与 Wall Kick",
    "arch_layer_1_i4": "Combo / B2B / T-Spin 判定",
    "arch_layer_2_title": "数据采集层",
    "arch_layer_2_i1": "每一步落点",
    "arch_layer_2_i2": "棋盘快照",
    "arch_layer_2_i3": "消行与攻击",
    "arch_layer_2_i4": "时间、速度与操作结果",
    "arch_layer_3_title": "多人同步层",
    "arch_layer_3_i1": "WebSocket 服务器",
    "arch_layer_3_i2": "房间与玩家状态",
    "arch_layer_3_i3": "攻击发送与接收",
    "arch_layer_3_i4": "1v1 / 多人模式扩展",
    "arch_flow_1_title": "对局数据",
    "arch_flow_1_desc": "玩家真实游玩产生的逐步记录",
    "arch_flow_2_title": "分析算法",
    "arch_flow_2_desc": "搜索候选路线并用评价函数打分",
    "arch_flow_3_title": "Replay 可视化",
    "arch_flow_3_desc": "时间线、推荐落点、数据面板、雷达图",
    "arch_support_title": "支撑系统",
    "arch_support_1_title": "三语本地化",
    "arch_support_1_desc": "中 / 日 / 英",
    "arch_support_2_title": "输入适配",
    "arch_support_2_desc": "键盘与手柄",
    "arch_support_3_title": "素材与 UI",
    "arch_support_3_desc": "大厅、棋盘、复盘界面",
    "arch_support_4_title": "开发工具链",
    "arch_support_4_desc": "Agent / MCP / CLI",
    "tech_kicker": "技术解释",
    "tech_h2": "这里的 AI 核心不是大语言模型，而是搜索与评价。",
    "tech_p1": "俄罗斯方块的 AI 分析更接近棋类游戏。原因是玩家并不是完全盲目地接收方块：现代规则中，玩家可以看到接下来的 5 个方块，还可以通过 Hold 保存一个方块。也就是说，系统可以在一定范围内预测接下来的局面，并搜索不同放法带来的结果。",
    "tech_p2": "因此，这里的 AI 核心并不需要 CNN、RNN，也不需要 LLM。它更像 AlphaGo 时代的思路：先生成候选操作，再向后搜索几步，最后用评价函数判断局面质量。评价函数会把 10 × 20 棋盘上的情况拆成许多指标，例如高度、空洞、表面凹凸、攻击机会、未来可持续性等。",
    "tech_p3": "当 Replay 分析某一步时，算法会比较玩家实际选择和搜索得到的推荐选择。如果两者差距很大，系统就能标出这一步可能是问题操作。这样，AI 的作用不是给出一句模糊评价，而是把“这个局面下更好的路线”计算出来，再通过界面展示给玩家。",
    "tech_p4": "项目本体基于 Godot 开发。Godot 是一个开源游戏引擎，定位上类似 Unity，但更轻量，适合快速制作 2D/3D 游戏原型并持续迭代。配合 Agent、MCP、CLI 化工具，小型项目可以更快地修改 UI、调试流程、整理文档和扩展工具链。",
    "tech_card_1_title": "Godot",
    "tech_card_1_desc": "负责游戏画面、UI、输入、场景和主要玩法逻辑。",
    "tech_card_2_title": "搜索算法",
    "tech_card_2_desc": "围绕 Next 5 与 Hold 搜索未来几步的候选路线。",
    "tech_card_3_title": "评价函数",
    "tech_card_3_desc": "把棋盘结构拆成多项指标，对每条路线进行打分。",
    "tech_card_4_title": "WebSocket",
    "tech_card_4_desc": "用于在线对战中的房间、同步和攻击传递。",
    "tech_card_5_title": "开发工具链",
    "tech_card_5_desc": "Agent / MCP / CLI 帮助快速完成修改、检查和文档化。",
    "closing_label": "结语",
    "closing_h2": "系统的重点，是把“玩家想变强”这件事拆成可以学习、可以操作、可以复盘、也可以验证的过程。",
    "closing_p": "Guidebook 解决“应该学什么、怎么亲手做一次”的问题；Replay 解决“哪里做得不好、有没有更好选择”的问题；多人对战则提供最终的验证环境。整个项目不是单个功能的集合，而是一条围绕玩家成长逆向设计出来的路径。"
  },
  "ja": {
    "page_title": "テトリス学習とリプレイシステム | コア・ドキュメント",
    "nav_foreword": "はじめに",
    "nav_intro": "イントロダクション",
    "nav_origin": "きっかけ",
    "nav_rules": "対戦ルール",
    "nav_journey": "プレイヤーの道のり",
    "nav_guidebook": "Guidebook",
    "nav_replay": "Replay",
    "nav_architecture": "アーキテクチャ",
    "nav_tech": "テクノロジー",
    "brand_title": "テトリス学習システム",
    "cover_author": "by WANHENG（バンコウ）",
    "cover_github": "GitHub",
    "cover_download": "ダウンロード",
    "cover_label": "コア・ドキュメント",
    "cover_h1": "テトリスの競技性に基づき、プレイヤーの上達を支援する学習とリプレイシステムを設計する。",
    "cover_lead": "テトリスは、ブロックを横一列に並べて消すだけではありません。対戦では、攻めと守りを両立させ、落下位置を先読みし、高速の中で的確に判断し、さらに試合後の振り返りで自分のプレイを修正していく——こうした要素が組み合わさり、継続的に競い合う競技システムを形成しています。このプロジェクトは「プレイヤーが初心者から上級者へどのように成長するか」を軸に、学習システム、リプレイ分析、および全体的な技術構造について議論します。",
    "cover_flow_1_title": "はじめに",
    "cover_flow_1_desc": "まず、テトリスがなぜ競技性を持っているのかを分かりやすい言葉で説明します。",
    "cover_flow_2_title": "きっかけ",
    "cover_flow_2_desc": "プレイヤーはレベルアップし、より強い相手を倒したいと考えていますが、十分に使いやすい補助ツールが不足しています。",
    "cover_flow_3_title": "デザイン",
    "cover_flow_3_desc": "Guidebook と Replay を通じて、「どう学ぶか」と「どこが間違っているか」をそれぞれ解決します。",
    "cover_flow_4_title": "システム構造",
    "cover_flow_4_desc": "最後に、ゲーム、データ収集、AI分析、マルチプレイ対戦、そしてツールチェーンがどのように組み合わされているかを説明します。",
    "intro_kicker": "イントロダクション：まずテトリスを理解する",
    "intro_h2": "テトリスは単に「ブロックを並べて消す」だけではありません。",
    "intro_p1": "多くの人がテトリスを思い浮かべるとき、ブロックが上から落ちてきて、それをきれいに並べて一列揃えて消す、というシンプルな画面を想像するでしょう。その側面だけを見れば、確かに1人用のパズルゲームです。しかし、テトリス、特に対戦型テトリスは、eスポーツに非常に近いシステムへと進化しています。",
    "intro_p2": "対戦では、単に「長く生き残る」ことだけを目指すわけではありません。ラインを消すたびに、それが相手への攻撃へと変換される可能性があります。攻撃を受けると、フィールドの底に「お邪魔ブロック（Garbage Lines）」が現れ、盤面がどんどん上に押し上げられます。いかに早くプレッシャーを与え、いかに安定してプレッシャーを処理できるかが、勝利へのカギとなります。",
    "intro_p3": "だからこそ、テトリスに真剣に取り組むことは、一つの競技種目をトレーニングすることと本質的に変わりません。操作スピードを鍛えるだけでなく、攻撃効率、積み方の構造、NEXT（次に来るブロック）の判断、Hold の使い方、T-Spin、Combo、Back-to-Back といった概念を理解する必要があります。これらの要素が互いに絡み合い、学習曲線と戦略的な深みを持ち、繰り返し振り返る価値のある競技システムを形作っています。",
    "intro_aside_h3": "テトリスを全く知らない方へ",
    "intro_aside_p": "対戦テトリスで重要なのは、ただラインを消すことではなく、それを「プレッシャー（攻撃）」に変換し、相手に送り込むことです。プレイヤーは攻撃を作り出すと同時に、受けた攻撃を処理しなければなりません。",
    "intro_fig1": "攻撃を受けると、プレッシャーはまず「アタックゲージ（攻撃バー）」に表示され、自身のライン消去によって相殺（相殺）するチャンスがあります。",
    "intro_fig2": "プレッシャーを処理できなかった場合、攻撃はフィールドの底の「お邪魔ブロック」に変わり、その後の展開を大きく変えてしまいます。",
    "intro_footnote": "これらの 1v1 の画像は基本的なメカニクスを示しています。攻撃は突然現れるのではなく、まずプレッシャーとして表示されます。自分のライン消去で相殺できなければ、そのプレッシャーは盤面に入り込み、処理しなければならない「お邪魔ブロック」になります。",
    "origin_kicker": "プロジェクトのきっかけ",
    "origin_h2": "上達したいプレイヤーには、自身の成長を直接助けてくれるツールが不足しがちです。",
    "origin_p1": "テトリスに触れたプレイヤーは、すぐに自然な目標を抱きます。それは、安定して生き残るだけでなく、対戦でより多くの、より強い相手を倒すことです。この目標が、攻撃方法、積み方、T-Spin、Combo、そしてプレッシャーの下で盤面を安定させる方法を学び続ける原動力となります。",
    "origin_p2": "確かに、既存の情報源にはテトリスWiki、動画チュートリアル、コミュニティの議論などが存在しますが、これらはデータベースのようなものです。概念を説明することはできても、プレイヤーがすぐに特定の局面に飛び込んで自分で試せるわけではありません。上級者のプレイを見せることはできても、一般プレイヤーが自身の対局で具体的にどのステップでミスをしたのかを指摘できるわけではありません。",
    "origin_p3": "したがって、システム設計の出発点は、単に普通のモードをもう一つ追加することではなく、「知識と操作を結びつけるツール」と、「プレイヤー自身の対局を分解して分析するツール」という、2種類の学習ツールを補うことです。前者が Guidebook、後者が Replay です。",
    "origin_aside_h3": "デザインの出発点",
    "origin_aside_p": "プレイヤーが本当に必要としているのは、実際に操作できる学習環境と、後から見返せるミス分析です。概念を読むだけでは不十分ですし、ただ繰り返しプレイするだけでも問題点に気づけるとは限りません。",
    "rules_kicker": "対戦ルールの最小限の解説",
    "rules_h2": "このプロジェクトを理解するには、まず「なぜライン消去が攻撃になるのか」を知る必要があります。",
    "rules_p1": "一般的なイメージでは、ラインを消すことは単なるスコア獲得です。しかし、対戦テトリスでは、ライン消去は同時に「攻撃行動」でもあります。価値の高い消し方をするほど、相手に大きなプレッシャーを与えられます。例えば、一度に4ラインを消すこと（Tetris）は、通常、バラバラに1～2ラインを消すよりも高い攻撃力（攻撃価値）を持ちます。",
    "rules_p2": "さらに一歩進んで、T-Spin Double のようなテクニックは2ラインしか消しませんが、操作の難易度と構造の要求が高いため、多くのルールでは Tetris に近い、あるいは同等の攻撃力を生み出します。これこそが、上級プレイヤーが自発的に T-Spin を学ぶ理由です。それは単なる魅せプレイではなく、限られたブロックをより高い効率で攻撃に変換するための手段なのです。",
    "rules_p3": "同時に、プレイヤーは次に来る5つのブロック（NEXT）を見ることができ、1つのブロックを Hold に一時保存（ホールド）することができます。これにより、テトリスは単なる反射神経のゲームではなくなり、チェスや将棋のように数手先の盤面を計画することが求められます。",
    "rules_stack_1_title": "盤面（フィールド）",
    "rules_stack_1_desc": "標準的なフィールドは 幅10マス × 高さ20マス です。頂上に近づくほど、ゲームオーバーのリスクが高まります。",
    "rules_stack_2_title": "Next 5 + Hold",
    "rules_stack_2_desc": "今後の5つのブロックを確認でき、1つを保存できるため、毎手ごとに計画的な要素が伴います。",
    "rules_stack_3_title": "攻撃とお邪魔ブロック（Garbage Lines）",
    "rules_stack_3_desc": "価値の高いライン消去は相手にお邪魔ブロックを送ります。これが盤面を押し上げ、操作可能なスペースを圧迫します。",
    "rules_stack_4_title": "相殺",
    "rules_stack_4_desc": "自分が攻撃を受けそうな時、ただ受動的に耐えるのではなく、自身のライン消去でプレッシャーの一部を打ち消すことができます。",
    "journey_kicker": "プレイヤーのニーズからのシステム逆算",
    "journey_h2": "機能から考えるのではなく、プレイヤーが「どうやって少しずつ強くなりたいか」を整理することから始めます。",
    "journey_step1_h3": "まず、自分が何をプレイしているのかを知る。",
    "journey_step1_p": "初心者が最初に必要とするのは複雑なテクニックではなく、基礎知識です。盤面の構造、ブロックの種類、Hold、Next、ライン消去、攻撃、お邪魔ブロック、そしてなぜ特定の消し方により高い価値があるのかを学びます。",
    "journey_step2_h3": "次に、一人で安全に練習できる場所を求める。",
    "journey_step2_p": "ソロの Marathon（マラソン）モードがこの役割を担います。相手に邪魔されることなく、操作、積み方、ライン消去のリズム、ゲームスピードに慣れることができます。この段階の目標は「安定してプレイし続けられるか」です。",
    "journey_step3_h3": "そして、どうすればもっと上手くプレイできるか考え始める。",
    "journey_step3_p": "ここで Guidebook の出番です。Wall Kick、Combo、T-Spin といったテクニックの背後にある原理を説明し、あらかじめ設定された盤面での「シミュレーション演習」を通じて、プレイヤーに実際に一度操作してもらいます。",
    "journey_step4_h3": "さらに進むと、自分のどこが間違っていたのかを知りたくなる。",
    "journey_step4_p": "ただプレイするだけでは同じミスを繰り返すかもしれません。Replay システムは対局を分解し、AIの推奨ルートを通じて弱点を素早く発見し、練習に活かすことができます。",
    "journey_step5_h3": "最後に、自身の成長を確認したいと願う。",
    "journey_step5_p": "長期的なデータ、レーダーチャート、対戦結果などを通じて自身の成長を確認できます。進歩は非常に小さく、体感しにくいこともありますが、データはその変化を記録として残してくれます。",
    "guide_kicker": "Guidebook：「概念を知る」から「実際にやってみる」へ",
    "guide_h2": "チュートリアルは、テキストや動画の中だけに留まるべきではありません。",
    "guide_p1": "T-Spin や Combo の動画を見た多くのプレイヤーも、実際にゲームに戻ると、どうやってその局面を作ればいいのか分からないことがよくあります。理由は簡単です。テトリスのテクニックは「見て理解する」だけでマスターできるものではなく、実際の盤面で移動、回転、落下、消去を自分で行ってはじめて、そのテクニックが成立する理由を理解できるからです。",
    "guide_p2": "そのため、Guidebook は従来のマニュアルではなく、学習のエントランスとしてデザインされています。まずテクニックを分かりやすい言葉で解説し、必要な前提知識と操作手順を示してから、シミュレーション演習へと導きます。シミュレーション演習では、盤面、現在のブロック、目標、成功条件がすべて固定されており、プレイヤーはその1つの知識ポイントにだけ集中することができます。",
    "guide_p3": "この目的は、学習のプレッシャーを小さく分割することです。プレイヤーは、実際の対局で都合の良い局面が運良く訪れるのを待つ必要も、相手に攻撃されながら新しいテクニックを学ぶ必要もありません。コントロールされた状況の中で、まずはコアとなるアクションを正しく一度実行できるのです。",
    "guide_module_1_title": "基礎知識",
    "guide_module_1_desc": "攻撃力、お邪魔ブロック、相殺、B2B、Combo などのルールを明確にします。",
    "guide_module_2_title": "操作セクション",
    "guide_module_2_desc": "Wall Kick、Combo、T-Spin Double などを学習可能な小さな章に分割します。",
    "guide_module_3_title": "シミュレーション演習",
    "guide_module_3_desc": "プレイヤーは固定された局面に移行し、実際の操作で目標アクションを1度完了させます。",
    "guide_module_4_title": "フィードバック",
    "guide_module_4_desc": "システムが目標達成を判定し、アクションが正しく成立したかをプレイヤーに知らせます。",
    "replay_kicker": "Replay：「そこそこ上手くできた」を観察可能なデータに変える",
    "replay_h2": "AI分析は対局の最中に直接介入するよりも、対局後に配置する方が適しています。",
    "replay_p1": "もしAIが対局中に「どこに置くべきか」を絶えず指示してきたら、短期的には便利に見えるかもしれませんが、プレイヤー自身の判断を妨げる恐れがあります。プレイヤーは盤面の理解を構築するのではなく、指示に従うだけの操作になってしまいます。プレッシャーの中で自立して選択をすることこそが、テトリスの核心的な楽しみの一つです。",
    "replay_p2": "そのため、AIの主な役割は対局後に置かれています。プレイヤーはまず本来のゲーム体験を損なうことなく1ゲームを完走します。終了後、Replay に入り、試合の録画を見るように自分の一手一手の選択を確認します。このように、AIはプレイヤーの代わりにプレイするのではなく、ゲームの外からプレイヤーが自分自身を理解する手助けをします。",
    "replay_p3": "Replay はまず、ステップごとの評価（スコア）を提示します。プレイヤーは1ゲームの中で損失の大きかった操作を素早く特定できます。問題を見つけると、プレイヤーは自然と「では、この手にもっと良い置き方はあったのか？」と疑問に思うでしょう。そこでシステムは AI が推奨する落下位置を表示し、今後の数手先のルートの参考を示します。これは抽象的なアドバイスではなく、「より良い選択」を直接盤面に提示するものです。",
    "replay_p4": "一方で、プレイヤーはゲーム全体を通してのパフォーマンスも知る必要があります。左側のデータパネルは1ゲーム全体の成績を集計し、レーダーチャートはスピード、攻撃、効率、構造、安定性、視野といった指標を視覚化します。一定期間後にこれらのデータを再比較すれば、少しずつ強くなっているという証拠を確認することができます。",
    "replay_aside_h3": "Replay の設計原則",
    "replay_aside_p": "AI はプレイヤーの操作権を奪うべきではありません。それは試合後のコーチのような存在です。まずプレイヤーに試合を完遂させ、後から問題を指摘し、模範解答を示し、そして成長を記録するのです。",
    "replay_fig1_cap": "Replay のインターフェースは、盤面、タイムライン、AIの推奨、解説パネルを一つにまとめ、プレイヤーが自分の選択を段階的に確認できるよう助けます。",
    "replay_fig2_cap": "1ゲームのサマリーデータにより、そのゲームの全体的なパフォーマンスを知ることができます。",
    "replay_fig3_cap": "レーダーチャートは、様々な能力の指標を比較しやすい一つの形に圧縮します。",
    "replay_note_h3": "1ゲームから長期的な変化へ",
    "replay_note_p": "1ゲームのサマリーは「このゲームで何が起きたか」に答え、レーダーチャートは「能力構造にどんな特徴があるか」に答えます。プレイヤーが繰り返しリプレイ分析を行うことで、毎回の経験を長期的な成長へと繋げることができます。",
    "arch_kicker": "プロジェクト構造",
    "arch_h2": "システム全体は、機能を単に寄せ集めたものではなく、プレイヤーの成長サイクルを中心に構成されています。",
    "arch_title_entry": "ロビー（エントランス）",
    "arch_entry_1": "ソロ練習",
    "arch_entry_2": "知識とシミュレーション演習",
    "arch_entry_3": "試合後分析",
    "arch_entry_4": "1v1 / マルチプレイ",
    "arch_connector": "プレイヤーは各モード間を循環する：練習 → 学習 → リプレイ → 対戦 → 再び練習",
    "arch_layer_1_title": "ゲーム実行レイヤー",
    "arch_layer_1_i1": "10 × 20 の盤面",
    "arch_layer_1_i2": "SRS 回転と Wall Kick",
    "arch_layer_1_i4": "Combo / B2B / T-Spin 判定",
    "arch_layer_2_title": "データ収集レイヤー",
    "arch_layer_2_i1": "毎手の落下位置",
    "arch_layer_2_i2": "盤面スナップショット",
    "arch_layer_2_i3": "ライン消去と攻撃",
    "arch_layer_2_i4": "時間、スピードと操作結果",
    "arch_layer_3_title": "マルチプレイ同期レイヤー",
    "arch_layer_3_i1": "WebSocket サーバー",
    "arch_layer_3_i2": "ルームとプレイヤー状態",
    "arch_layer_3_i3": "攻撃の送受信",
    "arch_layer_3_i4": "1v1 / マルチプレイ拡張",
    "arch_flow_1_title": "対局データ",
    "arch_flow_1_desc": "実際のプレイで生じた毎手の記録",
    "arch_flow_2_title": "分析アルゴリズム",
    "arch_flow_2_desc": "候補ルートを探索し、評価関数でスコアリング",
    "arch_flow_3_title": "Replay の視覚化",
    "arch_flow_3_desc": "タイムライン、推奨落下位置、データパネル、レーダーチャート",
    "arch_support_title": "サポートシステム",
    "arch_support_1_title": "三言語ローカライズ",
    "arch_support_1_desc": "中国語 / 日本語 / 英語",
    "arch_support_2_title": "入力対応",
    "arch_support_2_desc": "キーボードとコントローラー",
    "arch_support_3_title": "素材とUI",
    "arch_support_3_desc": "ロビー、盤面、リプレイ画面",
    "arch_support_4_title": "開発ツールチェーン",
    "arch_support_4_desc": "Agent / MCP / CLI",
    "tech_kicker": "技術的な解説",
    "tech_h2": "ここでの AI の中核は、大規模言語モデル (LLM) ではなく「探索と評価」です。",
    "tech_p1": "テトリスのAI分析はチェスや将棋のようなボードゲームに近いです。理由は、プレイヤーが完全にランダムにブロックを受け取るわけではないからです。ルールでは、プレイヤーは次の5つのブロック（NEXT）を見ることができ、Holdを使って1つのブロックを保存できます。つまり、システムはある程度先の盤面を予測し、異なる置き方がもたらす結果を探索することができるのです。",
    "tech_p2": "したがって、ここでのAIの中核にはCNN、RNN、あるいはLLMは必要ありません。AlphaGo時代の考え方に似ており、まず操作の候補を生成し、数手先まで探索してから、評価関数を用いて盤面の質を判断します。評価関数は、10 × 20 の盤面状況を「高さ」「空洞（穴）」「表面の凹凸」「攻撃チャンス」「将来の持続性」など、多くの指標に分解して計算します。",
    "tech_p3": "Replay が特定の手を分析する際、アルゴリズムはプレイヤーの実際の選択と、探索で得られた推奨の選択を比較します。もし両者の差が大きければ、システムはその手が「問題のある操作」だった可能性としてマークします。このように、AI の役割は曖昧な評価を下すことではなく、「この局面におけるより良いルート」を計算し、インターフェースを通じてプレイヤーに提示することです。",
    "tech_p4": "プロジェクト本体は Godot ベースで開発されています。Godot は Unity に似たオープンソースのゲームエンジンですが、より軽量で、2D/3D ゲームのプロトタイプを素早く作成し、継続的に反復するのに適しています。Agent、MCP、CLI ツールと組み合わせることで、小規模なプロジェクトでも UI の変更、フローのデバッグ、ドキュメントの整理、ツールチェーンの拡張をより迅速に行うことができます。",
    "tech_card_1_title": "Godot",
    "tech_card_1_desc": "ゲーム画面、UI、入力、シーン、および主要なゲームプレイのロジックを担当します。",
    "tech_card_2_title": "探索アルゴリズム",
    "tech_card_2_desc": "Next 5 と Hold を中心に、今後の数手先の候補ルートを探索します。",
    "tech_card_3_title": "評価関数",
    "tech_card_3_desc": "盤面構造を複数の指標に分解し、各ルートに対してスコアリングを行います。",
    "tech_card_4_title": "WebSocket",
    "tech_card_4_desc": "オンライン対戦におけるルーム管理、同期、および攻撃の伝達に使用されます。",
    "tech_card_5_title": "開発ツールチェーン",
    "tech_card_5_desc": "Agent / MCP / CLI により、修正、検査、ドキュメント化を迅速に行えます。",
    "closing_label": "おわりに",
    "closing_h2": "システムの最大のポイントは、「プレイヤーが強くなりたい」という思いを、学習可能で、操作可能で、リプレイ（振り返り）可能で、かつ検証可能なプロセスへと分解することにあります。",
    "closing_p": "Guidebook は「何を学ぶべきか、どうやって実際に手を動かすか」という問題を解決し、Replay は「どこが悪かったのか、もっと良い選択肢はなかったか」という問題を解決します。そしてマルチプレイ対戦が最終的な検証の場を提供します。プロジェクト全体は単なる機能の集合体ではなく、プレイヤーの成長を軸に逆算して設計された「上達への道」なのです。"
  },
  "en": {
    "page_title": "Tetris Learning & Replay System | Core Document",
    "nav_foreword": "Foreword",
    "nav_intro": "Intro",
    "nav_origin": "Origin",
    "nav_rules": "Rules",
    "nav_journey": "Journey",
    "nav_guidebook": "Guidebook",
    "nav_replay": "Replay",
    "nav_architecture": "Architecture",
    "nav_tech": "Tech",
    "brand_title": "Tetris Learning System",
    "cover_author": "by WANHENG（バンコウ）",
    "cover_github": "GitHub",
    "cover_download": "Download",
    "cover_label": "Core Document",
    "cover_h1": "Designing a learning and replay system to help players improve, based on the competitive nature of Tetris.",
    "cover_lead": "Tetris is not just about placing blocks in a row to clear them. In competitive play, players must balance offense and defense, plan their placements ahead, make split-second decisions at high speed, and refine their approach through post-match review. Together, these elements form a system of sustained competitive play. This project revolves around \"how players progress from beginners to advanced,\" focusing on the learning system, replay analysis, and overall technical architecture.",
    "cover_flow_1_title": "Foreword",
    "cover_flow_1_desc": "First, explain in plain language why Tetris is competitive.",
    "cover_flow_2_title": "Origin",
    "cover_flow_2_desc": "Players want to improve and beat stronger opponents, but lack sufficiently good auxiliary tools.",
    "cover_flow_3_title": "Design",
    "cover_flow_3_desc": "Solve \"how to learn\" and \"where mistakes are made\" through Guidebook and Replay respectively.",
    "cover_flow_4_title": "Structure",
    "cover_flow_4_desc": "Finally, explain how the game, data collection, AI analysis, multiplayer, and toolchain are combined.",
    "intro_kicker": "Intro: Understanding Tetris first",
    "intro_h2": "Tetris is not just \"placing blocks in a row to clear them.\"",
    "intro_p1": "When many people think of Tetris, they imagine a very simple scene: blocks falling, players aligning them, and clearing a full row. Looking only at this level, it is indeed a single-player puzzle game. However, Tetris, especially the competitive type, has evolved into a system very close to esports.",
    "intro_p2": "In a match, players don't simply pursue \"surviving longer.\" Every line clear can translate into an attack on the opponent. Upon receiving an attack, garbage lines appear at the bottom of the board, pushing the field continuously upwards. Whoever can create pressure faster and handle pressure more stably is closer to victory.",
    "intro_p3": "This is why taking Tetris seriously is no different from training for any competitive discipline. Players must not only build their operation speed, but also understand concepts like attack efficiency, stacking structure, preview judgment, the use of Hold, T-Spin, Combo, and Back-to-Back. These elements interweave to form a competitive system with a genuine learning curve, strategic depth, and real value in post-match review.",
    "intro_aside_h3": "For readers completely unfamiliar with Tetris",
    "intro_aside_p": "The focus of competitive Tetris is not just clearing lines, but converting line clears into pressure and applying that pressure to the opponent. Players must both generate attacks and handle the attacks they receive.",
    "intro_fig1": "When attacked, pressure is first displayed in the attack bar, giving the player a chance to cancel it out by clearing their own lines.",
    "intro_fig2": "If pressure is not handled, the attack turns into garbage lines at the bottom of the board, directly altering the subsequent situation.",
    "intro_footnote": "These two 1v1 images show the basic mechanism: attacks do not appear out of nowhere; they are first displayed as pressure. If the player does not cancel it out through their own line clears, the pressure enters the board, becoming garbage lines that must be dealt with.",
    "origin_kicker": "Project Origin",
    "origin_h2": "Players who want to improve often lack tools that can directly help them progress.",
    "origin_p1": "After encountering Tetris, players soon develop a natural goal: not only to survive stably but also to defeat more and stronger opponents in matches. This goal drives players to continue learning attack methods, stacking techniques, T-Spins, Combos, and how to maintain board stability under pressure.",
    "origin_p2": "Existing resources do include Tetris wikis, video tutorials, and community discussions, but these contents are usually more like databases. They can explain concepts, but not necessarily let players immediately jump into a fixed situation to try it themselves; they can showcase expert plays, but not necessarily point out exactly where an ordinary player went wrong in their own match.",
    "origin_p3": "Therefore, the starting point of the system design is not to add another normal mode, but to supplement two types of learning tools: one responsible for connecting knowledge with operation, and one responsible for dismantling and analyzing the player's own matches. The former is the Guidebook, and the latter is the Replay.",
    "origin_aside_h3": "Design Starting Point",
    "origin_aside_p": "What players really need is an operable learning environment and reviewable error analysis. Just reading concepts is not enough, and simply playing repeatedly does not guarantee discovering problems.",
    "rules_kicker": "Minimal explanation of match rules",
    "rules_h2": "To understand this project, you first need to know \"why clearing lines becomes an attack.\"",
    "rules_p1": "In the common impression, clearing a line is just scoring. But in competitive Tetris, clearing lines is also an act of attack. The more valuable the clear, the greater the pressure exerted on the opponent. For example, clearing four lines at once, which is a Tetris, usually has more attack value than clearing one or two lines scatteredly.",
    "rules_p2": "Going a step further, techniques like T-Spin Double only clear two lines, but due to higher operational difficulty and structural requirements, they can generate attack power close to or even equal to a Tetris in many rules. This is why advanced players proactively learn T-Spins: it's not showing off, but converting limited blocks into attacks more efficiently.",
    "rules_p3": "At the same time, players can also see the next 5 blocks and temporarily store one block in Hold. This makes Tetris no longer just a reaction game, but like a board game, requiring planning several steps ahead.",
    "rules_stack_1_title": "Board",
    "rules_stack_1_desc": "The standard field is 10 columns × 20 rows. The closer to the top, the higher the risk of topping out.",
    "rules_stack_2_title": "Next 5 + Hold",
    "rules_stack_2_desc": "Players can see the upcoming 5 blocks and temporarily store 1 block, meaning every move involves planning.",
    "rules_stack_3_title": "Attacks and Garbage Lines",
    "rules_stack_3_desc": "High-value clears send garbage lines to the opponent. Garbage lines raise the field and compress operable space.",
    "rules_stack_4_title": "Canceling",
    "rules_stack_4_desc": "When about to receive an attack, you can cancel out some pressure by clearing lines, rather than just passively enduring it.",
    "journey_kicker": "Reverse-engineering the system from player needs",
    "journey_h2": "The system does not list features first, but sorts out how players want to get stronger step by step.",
    "journey_step1_h3": "First, players need to know what they are playing.",
    "journey_step1_p": "What beginners need first are not complex techniques, but basic knowledge: board structure, block types, Hold, Next, clearing lines, attacks, garbage lines, and why some clears are more valuable.",
    "journey_step2_h3": "Then, players need a safe place to practice alone.",
    "journey_step2_p": "The single-player Marathon mode takes on this role. Players can get familiar with operations, stacking, rhythm, and speed without interference. The goal here is \"can I play stably?\"",
    "journey_step3_h3": "Next, players will start thinking about how to play better.",
    "journey_step3_p": "This is where the Guidebook comes in. It explains the principles behind Wall Kick, Combo, T-Spin, etc., and lets players actually practice them on preset boards via simulation drills.",
    "journey_step4_h3": "Further on, players want to know what they did wrong.",
    "journey_step4_p": "Playing more might just repeat mistakes. Replay breaks down the match, using AI recommendations to quickly spot weaknesses and guide future practice.",
    "journey_step5_h3": "Finally, players need to confirm their progress.",
    "journey_step5_p": "Players can confirm their growth through long-term data, radar charts, and match results. Progress is sometimes small and hard to feel, but data preserves these changes.",
    "guide_kicker": "Guidebook: From knowing concepts to hands-on experience",
    "guide_h2": "Tutorials shouldn't just be texts and videos.",
    "guide_p1": "Many players have seen videos of T-Spin or Combo, but back in the game, they still don't know how to set them up. The reason is simple: Tetris techniques require performing the actual moves on the board to truly grasp why they work.",
    "guide_p2": "Therefore, the Guidebook is not a manual but a learning entry point. It explains techniques simply, gives required background, and lets players enter a simulation drill where conditions are fixed to focus on one concept.",
    "guide_p3": "The purpose is to break down learning pressure. Players don't need to wait for the right moment in a real match or learn while being attacked. They can perform the core action correctly once in a controlled scenario.",
    "guide_module_1_title": "Basic Knowledge",
    "guide_module_1_desc": "Clarify rules like attack power, garbage lines, canceling, B2B, and Combos.",
    "guide_module_2_title": "Operation Chapters",
    "guide_module_2_desc": "Break down Wall Kick, Combo, T-Spin Double into small, learnable chapters.",
    "guide_module_3_title": "Simulation Drills",
    "guide_module_3_desc": "Players enter a fixed situation and complete a target move with real inputs.",
    "guide_module_4_title": "Feedback",
    "guide_module_4_desc": "The system checks if the goal was met, letting players know if their move worked.",
    "replay_kicker": "Replay: Turning 'felt like I played okay' into observable data",
    "replay_h2": "AI analysis is better placed after a match, rather than injected directly into it.",
    "replay_p1": "If AI constantly hints where to place during a game, it might seem convenient, but it disrupts player judgment. Independent choice under pressure is a core joy of Tetris.",
    "replay_p2": "Therefore, AI's main role is after the match. Players play fully, preserving the experience, then enter Replay to review choices like watching a sports tape.",
    "replay_p3": "Replay first gives step-by-step scoring. Players locate bad moves quickly, wonder \"is there a better way?\" and the system shows the AI recommended spot and route.",
    "replay_p4": "Also, players need overall performance. Data panels summarize the match, and radar charts visualize dimensions like speed, attack, efficiency, structure, stability, and vision.",
    "replay_aside_h3": "Replay Design Principles",
    "replay_aside_p": "AI shouldn't hijack player controls. It's more like a post-match coach: let the player finish, then point out mistakes, show reference answers, and record progress.",
    "replay_fig1_cap": "The Replay UI combines board, timeline, AI recommendations, and explanations to help players check their choices step-by-step.",
    "replay_fig2_cap": "Match summary data lets players know how their overall performance was.",
    "replay_fig3_cap": "Radar charts compress different ability dimensions into an easily comparable shape.",
    "replay_note_h3": "From single match to long-term change",
    "replay_note_p": "Match summaries answer \"what happened this game,\" while radar charts answer \"what are my skill characteristics.\" Repeated replays connect single-game experiences into long-term progress.",
    "arch_kicker": "Project Structure",
    "arch_h2": "The whole system is organized around the player's growth loop, not simply piling up features.",
    "arch_title_entry": "Lobby Entry",
    "arch_entry_1": "Solo Practice",
    "arch_entry_2": "Knowledge & Drills",
    "arch_entry_3": "Post-match Analysis",
    "arch_entry_4": "1v1 / Multiplayer",
    "arch_connector": "Players loop through modes: Practice → Learn → Replay → Match → Practice again",
    "arch_layer_1_title": "Game Engine Layer",
    "arch_layer_1_i1": "10 × 20 Board",
    "arch_layer_1_i2": "SRS Rotation & Wall Kick",
    "arch_layer_1_i4": "Combo / B2B / T-Spin Logic",
    "arch_layer_2_title": "Data Collection Layer",
    "arch_layer_2_i1": "Per-step placement",
    "arch_layer_2_i2": "Board snapshots",
    "arch_layer_2_i3": "Line clears and attacks",
    "arch_layer_2_i4": "Time, speed, operation results",
    "arch_layer_3_title": "Multiplayer Sync Layer",
    "arch_layer_3_i1": "WebSocket Server",
    "arch_layer_3_i2": "Rooms and player states",
    "arch_layer_3_i3": "Attack send/receive",
    "arch_layer_3_i4": "1v1 / Multiplayer extensions",
    "arch_flow_1_title": "Match Data",
    "arch_flow_1_desc": "Step-by-step logs from actual play",
    "arch_flow_2_title": "Analysis Algorithm",
    "arch_flow_2_desc": "Search candidate routes & score via evaluation function",
    "arch_flow_3_title": "Replay Visualization",
    "arch_flow_3_desc": "Timeline, recommended drops, data panels, radar charts",
    "arch_support_title": "Support System",
    "arch_support_1_title": "Trilingual Localization",
    "arch_support_1_desc": "CN / JA / EN",
    "arch_support_2_title": "Input Support",
    "arch_support_2_desc": "Keyboard & Gamepad",
    "arch_support_3_title": "Assets & UI",
    "arch_support_3_desc": "Lobby, board, replay interface",
    "arch_support_4_title": "Dev Toolchain",
    "arch_support_4_desc": "Agent / MCP / CLI",
    "tech_kicker": "Technical Explanation",
    "tech_h2": "The core of this AI is not LLMs, but search and evaluation.",
    "tech_p1": "Tetris AI analysis is closer to board games. Players don't receive blocks blindly: rules allow seeing the next 5 blocks and holding one. This means the system can predict future situations and search the results of different placements.",
    "tech_p2": "Therefore, the core AI doesn't need CNNs, RNNs, or LLMs. It's more like AlphaGo: generate candidate operations, search ahead, and judge board quality via an evaluation function.",
    "tech_p3": "When Replay analyzes a step, it compares the player's choice with the recommended one. If the gap is large, it marks it as a potential mistake.",
    "tech_p4": "The project is built on Godot, an open-source game engine. Combined with tools like Agent, MCP, and CLI, it allows rapid UI modification, flow debugging, and toolchain extension.",
    "tech_card_1_title": "Godot",
    "tech_card_1_desc": "Handles graphics, UI, input, scenes, and gameplay logic.",
    "tech_card_2_title": "Search Algorithm",
    "tech_card_2_desc": "Searches future routes around Next 5 and Hold.",
    "tech_card_3_title": "Evaluation Function",
    "tech_card_3_desc": "Breaks board structure into metrics and scores each route.",
    "tech_card_4_title": "WebSocket",
    "tech_card_4_desc": "Used for online rooms, sync, and passing attacks.",
    "tech_card_5_title": "Dev Toolchain",
    "tech_card_5_desc": "Agent / MCP / CLI help quickly complete modifications, checks, and docs.",
    "closing_label": "Closing",
    "closing_h2": "The focus of the system is to break down \"players wanting to get stronger\" into a learnable, operable, replayable, and verifiable process.",
    "closing_p": "Guidebook solves \"what to learn and how to do it\"; Replay solves \"what was bad and are there better choices\"; multiplayer provides the final validation. It's a path designed around player growth."
  }
};

const progress = document.querySelector("#scrollProgress");
const navLinks = [...document.querySelectorAll(".toc a")];
const sections = navLinks
  .map((link) => document.querySelector(link.getAttribute("href")))
  .filter(Boolean);

function updateProgress() {
  const max = document.documentElement.scrollHeight - window.innerHeight;
  const ratio = max <= 0 ? 0 : window.scrollY / max;
  progress.style.width = `${Math.min(100, Math.max(0, ratio * 100))}%`;

  let activeId = sections[0]?.id;
  for (const section of sections) {
    const rect = section.getBoundingClientRect();
    if (rect.top <= window.innerHeight * 0.38) {
      activeId = section.id;
    }
  }

  navLinks.forEach((link) => {
    link.classList.toggle("active", link.getAttribute("href") === `#${activeId}`);
  });
}

const revealObserver = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
      }
    });
  },
  { threshold: 0.12 }
);

document.querySelectorAll(".hero-media, .principle-list div, .journey article, .feature-item, .image-pair figure, .large-shot, .replay-points article, .stats-row figure, .mode-strip article, .arch-node, .tech-stack div").forEach((el) => {
  el.classList.add("reveal");
  revealObserver.observe(el);
});

window.addEventListener("scroll", updateProgress, { passive: true });
window.addEventListener("resize", updateProgress);
updateProgress();

// --- Language Switcher Logic ---

const langBtn = document.getElementById("lang-btn");
const langMenu = document.getElementById("lang-menu");
const langLabel = document.getElementById("current-lang-label");
const langItems = document.querySelectorAll("[data-lang]");

const langNames = {
  "ja": "日本語",
  "zh-CN": "简体中文",
  "en": "English"
};

// Determine initial language: URL ?lang= > localStorage > default "ja"
function getInitialLang() {
  const urlParams = new URLSearchParams(window.location.search);
  const urlLang = urlParams.get("lang");
  if (urlLang && translations[urlLang]) return urlLang;
  const storedLang = localStorage.getItem("app_lang");
  if (storedLang && translations[storedLang]) return storedLang;
  return "ja";
}

let currentLang = getInitialLang();

function setLanguage(lang) {
  if (!translations[lang]) return;
  currentLang = lang;
  document.documentElement.lang = lang;
  localStorage.setItem("app_lang", lang);
  langLabel.textContent = langNames[lang];

  // Update URL query parameter without reloading the page
  const url = new URL(window.location);
  url.searchParams.set("lang", lang);
  history.replaceState(null, "", url);

  document.querySelectorAll("[data-i18n]").forEach(el => {
    const key = el.getAttribute("data-i18n");
    if (translations[lang][key]) {
      el.textContent = translations[lang][key];
    }
  });

  // Update active state in menu
  langItems.forEach(btn => {
    if (btn.getAttribute("data-lang") === lang) {
      btn.classList.add("active");
    } else {
      btn.classList.remove("active");
    }
  });
}

langBtn.addEventListener("click", () => {
  const isExpanded = langBtn.getAttribute("aria-expanded") === "true";
  langBtn.setAttribute("aria-expanded", !isExpanded);
  langMenu.classList.toggle("show");
});

langItems.forEach(btn => {
  btn.addEventListener("click", (e) => {
    const selectedLang = e.target.getAttribute("data-lang");
    setLanguage(selectedLang);
    langBtn.setAttribute("aria-expanded", "false");
    langMenu.classList.remove("show");
  });
});

// Close menu on click outside
document.addEventListener("click", (e) => {
  if (!document.getElementById("lang-switcher").contains(e.target)) {
    langBtn.setAttribute("aria-expanded", "false");
    langMenu.classList.remove("show");
  }
});

// Initialize
setLanguage(currentLang);
