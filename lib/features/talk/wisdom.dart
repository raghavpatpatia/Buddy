/// Buddy's wisdom library: real verses and teachings with exact sources, meanings in plain words,
/// one action for today, and topic tags for retrieval. Scripture text is quoted only from here,
/// so the on-device model can explain but never invent a shloka.
///
/// Meanings are original renderings (not copied from modern translations). Modern self-help
/// books are summarised in our own words with credit, never quoted.
class Teaching {
  final String id, src, sa, mean, act;
  final List<String> tags;
  const Teaching(this.id, this.src, this.mean, this.act, this.tags, {this.sa = ''});
}

const teachings = <Teaching>[
  // ───────────── Bhagavad Gita ─────────────
  Teaching('g2.3', 'Bhagavad Gita 2.3', 'Don’t give in to this weakness, it doesn’t suit you. Shake off this small-heartedness and stand up.',
      'Do the one thing you’ve been avoiding for 10 minutes, right now.', ['motivation', 'courage', 'fear', 'sadness'],
      sa: 'klaibyaṁ mā sma gamaḥ pārtha… uttiṣṭha parantapa'),
  Teaching('g2.14', 'Bhagavad Gita 2.14', 'Heat and cold, pleasure and pain come and go like seasons. They are not permanent. Learn to bear them patiently.',
      'When a bad feeling comes today, name it and remind yourself: “this will pass.”', ['sadness', 'stress', 'patience', 'pain'],
      sa: 'mātrā-sparśās tu kaunteya śītoṣṇa-sukha-duḥkha-dāḥ… āgamāpāyino ’nityās'),
  Teaching('g2.20', 'Bhagavad Gita 2.20', 'The true Self is never born and never dies. It is not destroyed when the body is destroyed.',
      'Write one memory of the person you miss and one value of theirs you will carry forward.', ['death', 'grief', 'fear', 'self'],
      sa: 'na jāyate mriyate vā kadācin… na hanyate hanyamāne śarīre'),
  Teaching('g2.22', 'Bhagavad Gita 2.22', 'As a person throws away worn-out clothes and puts on new ones, the soul leaves a worn-out body and takes a new one.',
      'Be gentle with yourself today; grief is love with nowhere to go.', ['death', 'grief', 'change'],
      sa: 'vāsāṁsi jīrṇāni yathā vihāya'),
  Teaching('g2.38', 'Bhagavad Gita 2.38', 'Treat joy and sorrow, gain and loss, victory and defeat the same way, then act. That way you carry no burden.',
      'Before checking any result today (marks, money, likes), take three slow breaths first.', ['stress', 'failure', 'success', 'money', 'balance'],
      sa: 'sukha-duḥkhe same kṛtvā lābhālābhau jayājayau'),
  Teaching('g2.40', 'Bhagavad Gita 2.40', 'On this path no effort is ever wasted and nothing goes backwards. Even a little practice protects you from great fear.',
      'Do a tiny version of your goal today: 5 minutes still counts.', ['habits', 'motivation', 'failure', 'learning', 'discipline'],
      sa: 'nehābhikrama-nāśo ’sti pratyavāyo na vidyate'),
  Teaching('g2.41', 'Bhagavad Gita 2.41', 'A determined mind has one direction. A scattered mind splits into endless branches.',
      'Pick ONE priority for today and write it on top of your to-do list.', ['focus', 'decision', 'confusion', 'purpose'],
      sa: 'vyavasāyātmikā buddhir ekeha kuru-nandana'),
  Teaching('g2.47', 'Bhagavad Gita 2.47', 'You have a right to your work, but never to its results. Don’t let results be your motive, and don’t become attached to doing nothing either.',
      'Set a process goal for today (“code 1 hour”) instead of a result goal (“finish the game”).',
      ['work', 'karma', 'duty', 'anxiety', 'stress', 'result', 'career', 'exam'], sa: 'karmaṇy evādhikāras te mā phaleṣu kadācana'),
  Teaching('g2.48', 'Bhagavad Gita 2.48', 'Do your work steady in yoga, letting go of attachment, the same in success and failure. That evenness is called yoga.',
      'After your next task, whatever happened, say: “I did my part.”', ['failure', 'success', 'stress', 'work', 'balance'],
      sa: 'yoga-sthaḥ kuru karmāṇi saṅgaṁ tyaktvā dhanañjaya… samatvaṁ yoga ucyate'),
  Teaching('g2.50', 'Bhagavad Gita 2.50', 'Yoga is skill in action. One with a steady mind works with excellence and isn’t bound by results.',
      'Do today’s main task with full attention, with no phone nearby, as an offering of skill.', ['work', 'career', 'focus', 'excellence', 'coding'],
      sa: 'yogaḥ karmasu kauśalam'),
  Teaching('g2.56', 'Bhagavad Gita 2.56', 'One who isn’t shaken by sorrow, doesn’t crave pleasure, and is free of attachment, fear and anger is called a person of steady wisdom.',
      'When something irritates you today, pause 10 seconds before reacting.', ['peace', 'anger', 'fear', 'stress', 'mind'],
      sa: 'duḥkheṣv anudvigna-manāḥ sukheṣu vigata-spṛhaḥ'),
  Teaching('g2.62', 'Bhagavad Gita 2.62–63', 'Dwelling on objects creates attachment; attachment creates desire; frustrated desire becomes anger; anger clouds judgement; and confusion ruins you.',
      'Notice one craving today (reels, junk food, shopping) and break the chain early: walk away for 2 minutes.',
      ['desire', 'anger', 'addiction', 'scroll', 'mind', 'discipline'], sa: 'dhyāyato viṣayān puṁsaḥ saṅgas teṣūpajāyate… krodhād bhavati sammohaḥ'),
  Teaching('g2.70', 'Bhagavad Gita 2.70', 'Rivers keep pouring into the ocean, yet it stays calm and full. One whom desires enter like that finds peace, not the one who chases them.',
      'Unfollow or mute one account that makes you want more than you need.', ['desire', 'peace', 'comparison', 'contentment', 'money'],
      sa: 'āpūryamāṇam acala-pratiṣṭhaṁ samudram āpaḥ praviśanti yadvat'),
  Teaching('g3.8', 'Bhagavad Gita 3.8', 'Do your duty; action is better than inaction. Without action you can’t even maintain your body.',
      'Start with the smallest physical step of your task: open the file, put on the shoes.', ['laziness', 'procrastination', 'duty', 'motivation', 'work'],
      sa: 'niyataṁ kuru karma tvaṁ karma jyāyo hy akarmaṇaḥ'),
  Teaching('g3.13', 'Bhagavad Gita 3.13', 'Those who share before they eat are freed; those who cook only for themselves eat their own sin.',
      'Share something today: a meal, your knowledge, or a small donation.', ['giving', 'money', 'gratitude', 'relationships']),
  Teaching('g3.21', 'Bhagavad Gita 3.21', 'Whatever a great person does, others follow. The standard they set, the world follows.',
      'Be the example: write clean code, be on time, help a junior today.', ['leadership', 'career', 'work', 'responsibility'],
      sa: 'yad yad ācarati śreṣṭhas tat tad evetaro janaḥ'),
  Teaching('g3.27', 'Bhagavad Gita 3.27', 'All actions are done by the forces of nature, but the mind confused by ego thinks “I am the doer.”',
      'When praised today, quietly credit the people and luck that helped you.', ['ego', 'success', 'humility']),
  Teaching('g3.35', 'Bhagavad Gita 3.35', 'Better your own path done imperfectly than another’s done perfectly. Following another’s path is full of fear.',
      'Stop comparing for a day: list 3 things that are uniquely your path.', ['comparison', 'purpose', 'career', 'jealousy', 'self'],
      sa: 'śreyān sva-dharmo viguṇaḥ para-dharmāt sv-anuṣṭhitāt'),
  Teaching('g3.37', 'Bhagavad Gita 3.37', 'It is desire, which turns into anger, born of restlessness. It is all-devouring; know it as the enemy here.',
      'When anger rises today, drink a glass of water slowly before speaking.', ['anger', 'desire', 'mind'], sa: 'kāma eṣa krodha eṣa rajo-guṇa-samudbhavaḥ'),
  Teaching('g4.7', 'Bhagavad Gita 4.7–8', 'Whenever righteousness declines and wrong rises, I manifest myself, to protect the good and restore balance.',
      'Do one right thing today even if nobody is watching.', ['faith', 'hope', 'dharma', 'injustice'], sa: 'yadā yadā hi dharmasya glānir bhavati bhārata'),
  Teaching('g4.34', 'Bhagavad Gita 4.34', 'Learn the truth by approaching the wise with humility, sincere questions and service. They will teach you.',
      'Ask one senior or mentor a genuine question this week.', ['learning', 'mentor', 'humility', 'career']),
  Teaching('g4.38', 'Bhagavad Gita 4.38', 'Nothing in this world purifies like knowledge. One who is perfected in practice finds it within in time.',
      'Learn one new concept today and explain it in one sentence.', ['learning', 'knowledge', 'coding'], sa: 'na hi jñānena sadṛśaṁ pavitram iha vidyate'),
  Teaching('g4.39', 'Bhagavad Gita 4.39', 'The one with faith, who is devoted to it and has mastered the senses, gains knowledge, and soon finds supreme peace.',
      'Study 25 minutes with your phone in another room.', ['learning', 'discipline', 'focus', 'faith'], sa: 'śraddhāvāl labhate jñānaṁ tat-paraḥ saṁyatendriyaḥ'),
  Teaching('g4.40', 'Bhagavad Gita 4.40', 'The ignorant, faithless and doubting person is lost. For the doubter there is no happiness in this world or the next.',
      'Make the decision you’re stuck on with the info you have; set a date to review it.', ['doubt', 'decision', 'confusion', 'fear'],
      sa: 'saṁśayātmā vinaśyati'),
  Teaching('g5.10', 'Bhagavad Gita 5.10', 'One who works offering results to the Divine, giving up attachment, isn’t touched by sin, like a lotus leaf isn’t wet by water.',
      'Do one task today purely for its own sake, without checking how it will be judged.', ['stress', 'detachment', 'work', 'peace']),
  Teaching('g6.5', 'Bhagavad Gita 6.5', 'Lift yourself by your own self; don’t let yourself sink. The mind is your best friend and also your worst enemy.',
      'Talk to yourself today the way you’d talk to a friend you believe in.', ['motivation', 'self', 'mind', 'sadness', 'confidence'],
      sa: 'uddhared ātmanātmānaṁ nātmānam avasādayet'),
  Teaching('g6.6', 'Bhagavad Gita 6.6', 'For one who has conquered the mind, the mind is a friend. For one who hasn’t, it acts like an enemy.',
      'Keep one promise to yourself today, however small.', ['mind', 'discipline', 'habits', 'self'], sa: 'bandhur ātmātmanas tasya yenātmaivātmanā jitaḥ'),
  Teaching('g6.16', 'Bhagavad Gita 6.16–17', 'Yoga isn’t for one who eats too much or too little, sleeps too much or too little. Balanced food, rest, work and play end suffering.',
      'Sleep 7–8 hours tonight; no screen 30 minutes before bed.', ['health', 'balance', 'sleep', 'food', 'stress'],
      sa: 'yuktāhāra-vihārasya yukta-ceṣṭasya karmasu'),
  Teaching('g6.26', 'Bhagavad Gita 6.26', 'Wherever the restless mind wanders, bring it back again and again to the Self.',
      'Meditate 5 minutes: each time the mind wanders, gently bring it back to the breath.', ['focus', 'meditation', 'mind', 'anxiety', 'scroll'],
      sa: 'yato yato niścarati manaś cañcalam asthiram'),
  Teaching('g6.32', 'Bhagavad Gita 6.32', 'The highest yogi sees others’ joy and pain as their own.',
      'Ask someone today how they’re really doing, and listen fully.', ['empathy', 'relationships', 'kindness', 'family', 'friends']),
  Teaching('g6.35', 'Bhagavad Gita 6.35', 'Yes, the mind is restless and hard to control. But it is controlled through practice and detachment.',
      'Pick one habit and do it at the same time for 7 days.', ['focus', 'discipline', 'habits', 'mind', 'scroll', 'addiction'],
      sa: 'abhyāsena tu kaunteya vairāgyeṇa ca gṛhyate'),
  Teaching('g6.40', 'Bhagavad Gita 6.40', 'One who does good never comes to a bad end, neither here nor hereafter.',
      'Continue the good thing you started, even if results are slow.', ['fear', 'failure', 'hope', 'faith'], sa: 'na hi kalyāṇa-kṛt kaścid durgatiṁ tāta gacchati'),
  Teaching('g9.22', 'Bhagavad Gita 9.22', 'Those who worship me with undivided focus, I carry what they lack and protect what they have.',
      'Write down 3 things you’re grateful for, then let go of one worry.', ['faith', 'anxiety', 'money', 'fear', 'surrender'],
      sa: 'yoga-kṣemaṁ vahāmy aham'),
  Teaching('g11.33', 'Bhagavad Gita 11.33', 'Arise and win glory; the outcome is already set. Be just the instrument.',
      'Treat today’s big task as your role to play, not a test of your worth.', ['ego', 'stress', 'courage', 'work']),
  Teaching('g12.13', 'Bhagavad Gita 12.13–14', 'One who hates no being, is friendly and compassionate, free of “mine” and ego, equal in pain and pleasure, and forgiving, is dear to me.',
      'Forgive one small thing someone did, without telling them.', ['relationships', 'anger', 'kindness', 'forgiveness', 'ego'],
      sa: 'adveṣṭā sarva-bhūtānāṁ maitraḥ karuṇa eva ca'),
  Teaching('g12.15', 'Bhagavad Gita 12.15', 'One who doesn’t disturb the world and isn’t disturbed by it, free from excitement, anger and fear, is dear to me.',
      'Avoid one argument today that doesn’t really matter.', ['peace', 'anger', 'relationships', 'stress']),
  Teaching('g13.8', 'Bhagavad Gita 13.8', 'Humility, lack of pretence, non-violence, patience, honesty, serving one’s teacher, purity, steadiness and self-control: this is knowledge.',
      'Admit one mistake openly today. It’s a strength.', ['ego', 'humility', 'learning', 'honesty']),
  Teaching('g16.21', 'Bhagavad Gita 16.21', 'Desire, anger and greed are three gates to self-destruction. Give up all three.',
      'Pause before one impulse buy or angry message today.', ['anger', 'greed', 'desire', 'money', 'addiction'], sa: 'kāmaḥ krodhas tathā lobhas'),
  Teaching('g17.15', 'Bhagavad Gita 17.15', 'Speech that doesn’t hurt, is truthful, pleasant and helpful is the discipline of speech.',
      'Before sending a message today, check: is it true, kind and useful?', ['communication', 'relationships', 'anger', 'honesty']),
  Teaching('g17.20', 'Bhagavad Gita 17.20', 'A gift given because it is right to give, to a worthy person, at the right time and place, expecting nothing back, is pure.',
      'Give something small today without expecting thanks.', ['giving', 'money', 'charity', 'gratitude']),
  Teaching('g18.48', 'Bhagavad Gita 18.48', 'Don’t abandon the work suited to you even if it has flaws. Every action has some fault, as fire has smoke.',
      'Ship the “good enough” version today; improve it tomorrow.', ['perfectionism', 'work', 'coding', 'procrastination', 'fear']),
  Teaching('g18.66', 'Bhagavad Gita 18.66', 'Let go of all worries and take refuge in me. I will free you from all burdens. Do not grieve.',
      'Write your worry on paper, fold it, and do one useful thing instead.', ['fear', 'anxiety', 'faith', 'grief', 'surrender'],
      sa: 'sarva-dharmān parityajya mām ekaṁ śaraṇaṁ vraja… mā śucaḥ'),
  Teaching('g18.78', 'Bhagavad Gita 18.78', 'Where there is Krishna, master of yoga, and Arjuna, the archer, there is prosperity, victory and wisdom.',
      'Combine wisdom and action today: plan for 5 minutes, then execute.', ['success', 'wealth', 'action', 'planning']),

  // ───────────── Vedas & Upanishads ─────────────
  Teaching('rv1.89', 'Rig Veda 1.89.1', 'Let noble thoughts come to us from every direction.',
      'Read or watch one thing today from a field outside your own.', ['learning', 'openness', 'curiosity'], sa: 'ā no bhadrāḥ kratavo yantu viśvataḥ'),
  Teaching('rv1.164', 'Rig Veda 1.164.46', 'Truth is one; the wise call it by many names.',
      'Respect one view today that differs from yours.', ['faith', 'respect', 'relationships'], sa: 'ekaṁ sad viprā bahudhā vadanti'),
  Teaching('rv10.191', 'Rig Veda 10.191.2', 'Walk together, speak together, let your minds be in harmony.',
      'In your next team chat, listen fully before replying.', ['teamwork', 'relationships', 'family', 'communication'], sa: 'saṁ gacchadhvaṁ saṁ vadadhvam'),
  Teaching('gayatri', 'Gayatri Mantra, Rig Veda 3.62.10', 'We meditate on the radiant light of the Divine; may it inspire and illuminate our intellect.',
      'Chant or read the Gayatri once this morning before opening your phone.', ['focus', 'learning', 'morning', 'mind', 'faith'],
      sa: 'oṁ bhūr bhuvaḥ svaḥ tat savitur vareṇyaṁ bhargo devasya dhīmahi dhiyo yo naḥ pracodayāt'),
  Teaching('katha3.14', 'Katha Upanishad 1.3.14', 'Arise! Awake! Approach the great teachers and learn. The path is sharp like a razor’s edge, hard to walk, say the wise.',
      'Wake up 15 minutes earlier tomorrow and use it for your most important goal.', ['motivation', 'learning', 'discipline', 'morning'],
      sa: 'uttiṣṭhata jāgrata prāpya varān nibodhata'),
  Teaching('katha2.2', 'Katha Upanishad 1.2.2', 'Both the good (shreyas) and the pleasant (preyas) come to us. The wise choose the good; the foolish choose the pleasant out of craving.',
      'Choose the good over the pleasant once today: a lesson instead of reels.', ['discipline', 'scroll', 'desire', 'decision', 'habits']),
  Teaching('katha3.3', 'Katha Upanishad 1.3.3–4', 'The Self is the rider, the body the chariot, the intellect the charioteer, the mind the reins, and the senses the horses.',
      'Let your intellect hold the reins today: decide your schedule before the phone decides it.', ['mind', 'focus', 'discipline', 'self']),
  Teaching('isha1', 'Isha Upanishad 1', 'Everything here is pervaded by the Divine. Enjoy it by letting go; don’t covet anyone’s wealth.',
      'Enjoy one thing you already own today instead of buying something new.', ['money', 'greed', 'contentment', 'desire', 'comparison'],
      sa: 'īśāvāsyam idaṁ sarvaṁ… tena tyaktena bhuñjīthā mā gṛdhaḥ kasya svid dhanam'),
  Teaching('taitt11', 'Taittiriya Upanishad 1.11.1', 'Speak the truth. Follow dharma. Never neglect your self-study.',
      'Spend 20 minutes on self-study today: a lesson, a book, a tutorial.', ['learning', 'honesty', 'discipline', 'dharma'],
      sa: 'satyaṁ vada dharmaṁ cara svādhyāyān mā pramadaḥ'),
  Teaching('taitt11b', 'Taittiriya Upanishad 1.11.2', 'Treat your mother as divine, your father as divine, your teacher as divine, your guest as divine.',
      'Call your parents today, just to talk.', ['family', 'gratitude', 'respect', 'relationships'], sa: 'mātṛ devo bhava pitṛ devo bhava ācārya devo bhava atithi devo bhava'),
  Teaching('mundaka', 'Mundaka Upanishad 3.1.6', 'Truth alone triumphs, not falsehood.',
      'Correct one small untruth today, even in a code comment or report.', ['honesty', 'courage', 'integrity'], sa: 'satyam eva jayate'),
  Teaching('brihad1', 'Brihadaranyaka Upanishad 1.3.28', 'Lead me from the unreal to the real, from darkness to light, from death to immortality.',
      'In a dark mood today, do one small thing that brings light: sunlight, a walk, a call.', ['fear', 'hope', 'sadness', 'faith'],
      sa: 'asato mā sad gamaya, tamaso mā jyotir gamaya, mṛtyor mā amṛtaṁ gamaya'),
  Teaching('brihad4', 'Brihadaranyaka Upanishad 4.4.5', 'As your deepest desire is, so is your will; as your will is, so are your deeds; as your deeds are, so is your destiny.',
      'Write your deepest goal in one line and keep it as your phone wallpaper.', ['purpose', 'habits', 'motivation', 'destiny']),
  Teaching('tat', 'Chandogya Upanishad 6.8.7', 'That thou art (tat tvam asi): what you seek is already within you.',
      'Spend 5 quiet minutes today with no input: no music, no phone.', ['self', 'peace', 'loneliness', 'purpose'], sa: 'tat tvam asi'),
  Teaching('sahana', 'Taittiriya / Katha shanti mantra', 'May we be protected together, nourished together, work with great energy together. May our study be brilliant; may we never hate each other.',
      'Study or code together with a friend this week.', ['learning', 'teamwork', 'friends'], sa: 'oṁ saha nāv avatu… mā vidviṣāvahai'),

  // ───────────── Ramayana ─────────────
  Teaching('ram_exile', 'Ramayana, Ayodhya Kanda', 'When the crown was taken from him and exile announced instead, Rama’s face showed no anger. He accepted it calmly and kept his dharma.',
      'When a plan breaks today, respond with “okay, what’s my next right step?”', ['change', 'stress', 'loss', 'patience', 'duty']),
  Teaching('ram_hanuman_strength', 'Ramayana, Kishkindha Kanda', 'Hanuman had forgotten his own strength until Jambavan reminded him. Then he leapt across the ocean.',
      'List 3 hard things you’ve already done. You’re stronger than you remember.', ['confidence', 'self-doubt', 'motivation', 'fear']),
  Teaching('ram_kaaj', 'Ramcharitmanas, Sundar Kand (Tulsidas)', '“Ram kaaj kinhe binu mohi kahan bishram”: Hanuman refused to rest until Rama’s work was done.',
      'Finish one pending task completely before starting anything new today.', ['focus', 'discipline', 'work', 'procrastination'],
      sa: 'rāma kāju kīnheṁ binu mohi kahāṁ biśrāma'),
  Teaching('ram_bharat', 'Ramayana, Ayodhya Kanda', 'Bharata refused the throne meant for Rama, ruled only as a caretaker with Rama’s sandals on it, and lived simply.',
      'Use any power you have today (team lead, elder sibling) as service, not status.', ['leadership', 'ego', 'family', 'loyalty']),
  Teaching('ram_squirrel', 'Ramayana (folk tradition)', 'While mighty vanaras carried boulders for the bridge to Lanka, a little squirrel rolled in sand and shook it off between the stones. Rama honoured its effort.',
      'Make a small contribution today; small efforts matter.', ['habits', 'teamwork', 'motivation', 'humility']),
  Teaching('ram_shabari', 'Ramayana, Aranya Kanda', 'Shabari waited years with patient devotion, preparing for Rama every day. When he came, he accepted her humble berries with love.',
      'Keep preparing for your goal today even if the result is far away.', ['patience', 'faith', 'devotion', 'consistency']),
  Teaching('ram_ravana', 'Ramayana', 'Ravana was a great scholar and devotee of Shiva, yet ego and uncontrolled desire destroyed him.',
      'Notice one moment of ego today and choose humility.', ['ego', 'desire', 'anger']),
  Teaching('ram_vibhishana', 'Ramayana, Yuddha Kanda', 'Vibhishana told his own brother Ravana the truth, and when he wouldn’t listen, chose dharma over family loyalty.',
      'Say the honest thing kindly today, even if it’s uncomfortable.', ['courage', 'honesty', 'decision', 'integrity']),
  Teaching('ram_setu', 'Ramayana, Yuddha Kanda', 'Nala and Nila, the vanara army and faith in Rama’s name built a bridge across the sea: skill, teamwork and faith together.',
      'Break a big project into stones: plan the first three steps today.', ['teamwork', 'faith', 'planning', 'work']),

  // ───────────── Mahabharata (Jaya) ─────────────
  Teaching('mb_birdeye', 'Mahabharata, Adi Parva', 'When Drona asked his students what they saw, others saw the tree, the branches and the bird. Arjuna said, “Only the bird’s eye.” Only he was allowed to shoot.',
      'Work 45 minutes on one task with every other tab closed.', ['focus', 'goal', 'coding', 'study', 'scroll']),
  Teaching('mb_ekalavya', 'Mahabharata, Adi Parva', 'Ekalavya was refused by Drona, so he made a clay image of the teacher and practised alone until he became a master archer.',
      'Learn something today from free resources; no teacher needed to start.', ['learning', 'self-study', 'motivation', 'discipline']),
  Teaching('mb_yaksha_wonder', 'Mahabharata, Vana Parva (Yaksha Prashna)', 'Asked “What is the greatest wonder?”, Yudhishthira said: every day people die, yet the living act as if they will live forever.',
      'Do today the thing you keep saying you’ll “do someday”.', ['death', 'time', 'purpose', 'procrastination']),
  Teaching('mb_yaksha_mind', 'Mahabharata, Vana Parva (Yaksha Prashna)', 'Asked “What is faster than the wind?”, Yudhishthira answered: the mind.',
      'Catch your mind racing once today; slow down with 5 deep breaths.', ['mind', 'anxiety', 'focus']),
  Teaching('mb_yaksha_gain', 'Mahabharata, Vana Parva (Yaksha Prashna)', 'The best of gains is health; the best happiness is contentment.',
      'Count today’s gains in health and contentment, not just money.', ['health', 'contentment', 'money', 'gratitude']),
  Teaching('mb_vidura6', 'Mahabharata, Udyoga Parva (Vidura Niti 33)', 'One who wants prosperity must give up six faults: excessive sleep, drowsiness, fear, anger, laziness and procrastination.',
      'Pick one of the six you struggle with most and beat it once today.', ['wealth', 'laziness', 'procrastination', 'success', 'discipline', 'sleep'],
      sa: 'ṣaḍ doṣāḥ puruṣeṇeha hātavyā bhūtim icchatā… nidrā tandrī bhayaṁ krodha ālasyaṁ dīrghasūtratā'),
  Teaching('mb_dice', 'Mahabharata, Sabha Parva', 'Yudhishthira, wise in everything else, lost his kingdom, brothers and wife in a game of dice he couldn’t stop playing.',
      'Avoid gambling, betting apps and “get rich quick” schemes; set a hard limit on risky money.', ['money', 'addiction', 'risk', 'gambling', 'investing']),
  Teaching('mb_karna', 'Mahabharata', 'Karna was generous and brave, but loyalty to the wrong friend pulled him onto the wrong side.',
      'Notice who you spend the most time with; are they pulling you up?', ['friends', 'relationships', 'company', 'decision']),
  Teaching('mb_abhimanyu', 'Mahabharata, Drona Parva', 'Abhimanyu knew how to enter the chakravyuha but not how to exit, and was trapped.',
      'Before starting any big commitment (loan, project, investment), plan your exit.', ['planning', 'learning', 'investing', 'risk', 'money']),
  Teaching('mb_peace', 'Mahabharata, Udyoga Parva', 'Before the war, Krishna went as a peace envoy and asked for just five villages for the Pandavas. War came only when peace was refused.',
      'In any conflict today, offer one reasonable compromise first.', ['conflict', 'relationships', 'anger', 'family']),
  Teaching('manu_dharma', 'Manusmriti 8.15 (quoted widely with the Mahabharata)', 'Dharma protects those who protect it.',
      'Keep your word today in one small thing.', ['dharma', 'integrity', 'faith'], sa: 'dharmo rakṣati rakṣitaḥ'),

  // ───────────── Wealth: Chanakya & Arthashastra ─────────────
  Teaching('artha_root', 'Arthashastra 1.19 (Chanakya)', 'The root of wealth is effort and enterprise. Without it, even existing wealth is lost.',
      'Spend 30 minutes today on a skill that increases your earning power.', ['wealth', 'money', 'work', 'career', 'laziness'], sa: 'arthasya mūlam utthānam'),
  Teaching('chanakya_save', 'Chanakya Niti', 'Save wealth for times of misfortune.',
      'Start or top up an emergency fund: aim for 6 months of expenses.', ['money', 'saving', 'emergency', 'wealth']),
  Teaching('chanakya_drop', 'Chanakya Niti', 'Drop by drop the pot fills. So too are knowledge, dharma and wealth gathered.',
      'Set up a small automatic monthly SIP or saving, even ₹500.', ['saving', 'investing', 'habits', 'learning', 'wealth', 'money'],
      sa: 'jala-bindu-nipātena kramaśaḥ pūryate ghaṭaḥ'),
  Teaching('chanakya_vidya', 'Chanakya Niti', 'Knowledge is your friend when travelling, a wife at home, medicine when sick, and dharma after death.',
      'Invest in one course or book this month. It compounds forever.', ['learning', 'wealth', 'career']),
  Teaching('chanakya_debt', 'Chanakya Niti', 'A debt left unpaid, an enemy left unchecked and a disease left untreated keep growing. Finish them early.',
      'List your debts and pay extra on the costliest one this month.', ['debt', 'money', 'loan', 'emi', 'health']),

  // ───────────── Wealth classics (public domain) ─────────────
  Teaching('bab_purse', 'The Richest Man in Babylon (G. S. Clason, 1926)', 'Start thy purse to fattening: of every ten coins you earn, keep at least one for yourself, before spending anything.',
      'Move 10% of your income to savings the day it arrives.', ['saving', 'money', 'wealth', 'salary', 'habits']),
  Teaching('bab_control', 'The Richest Man in Babylon (G. S. Clason, 1926)', 'Control thy expenditures: what we call “necessary expenses” always grow to equal our income unless we decide otherwise.',
      'Check last month’s spending and cut one subscription or habit.', ['money', 'spending', 'saving', 'budget']),
  Teaching('bab_multiply', 'The Richest Man in Babylon (G. S. Clason, 1926)', 'Make thy gold multiply: put saved money to work so it earns more, like slaves working for you.',
      'Learn how index funds work this week; consider a monthly SIP.', ['investing', 'money', 'wealth', 'compounding']),
  Teaching('bab_guard', 'The Richest Man in Babylon (G. S. Clason, 1926)', 'Guard thy treasures from loss: prefer safety of principal over tempting high returns; take advice from those experienced with money.',
      'Before any investment ask: “Can I lose all of this? Who benefits if I buy?”', ['investing', 'risk', 'money', 'scam']),
  Teaching('bab_earn', 'The Richest Man in Babylon (G. S. Clason, 1926)', 'Increase thy ability to earn: the more skill you have, the more you can earn.',
      'Pick one high-value skill (e.g. shaders, system design) and practise 30 min today.', ['career', 'learning', 'wealth', 'skills']),
  Teaching('allen_mind', 'As a Man Thinketh (James Allen, 1903)', 'A person is literally what they think. Circumstances don’t make a person; they reveal them.',
      'Replace one negative thought about yourself today with a true, kinder one.', ['mind', 'self', 'motivation', 'confidence']),
  Teaching('smiles_help', 'Self-Help (Samuel Smiles, 1859)', 'Heaven helps those who help themselves. Steady, patient effort beats talent without work.',
      'Do one thing today that future-you will thank you for.', ['motivation', 'discipline', 'work', 'success']),
  Teaching('aurelius_control', 'Meditations (Marcus Aurelius)', 'You have power over your mind, not outside events. Realise this, and you will find strength.',
      'Split today’s worry into “in my control” and “not”; act only on the first list.', ['stress', 'anxiety', 'control', 'mind']),
  Teaching('aurelius_obstacle', 'Meditations (Marcus Aurelius)', 'The obstacle to action becomes the way forward. What stands in the way becomes the way.',
      'Treat today’s bug or problem as the exact lesson you needed.', ['failure', 'coding', 'obstacles', 'motivation']),

  // ───────────── Modern ideas (our summaries, with credit) ─────────────
  Teaching('atomic_1pct', 'Idea from “Atomic Habits” (James Clear)', 'Small 1% improvements compound into huge results. You don’t rise to your goals; you fall to your systems.',
      'Make one good habit 2 minutes long and do it today.', ['habits', 'discipline', 'motivation', 'growth']),
  Teaching('atomic_identity', 'Idea from “Atomic Habits” (James Clear)', 'Lasting change comes from identity: every action is a vote for the person you want to become.',
      'Do one action today that a “disciplined developer” would do.', ['habits', 'self', 'identity', 'discipline']),
  Teaching('atomic_env', 'Idea from “Atomic Habits” (James Clear)', 'Make good habits obvious and easy, and bad habits invisible and hard. Design your environment.',
      'Move Instagram off your home screen; put your flute or book in sight.', ['habits', 'scroll', 'addiction', 'environment']),
  Teaching('deepwork', 'Idea from “Deep Work” (Cal Newport)', 'Focused, distraction-free work produces rare, valuable results; shallow multitasking doesn’t.',
      'Block 90 minutes today for deep work with notifications off.', ['focus', 'coding', 'career', 'work', 'scroll']),
  Teaching('pom_enough', 'Idea from “The Psychology of Money” (Morgan Housel)', 'The hardest financial skill is getting the goalpost to stop moving: knowing when you have enough.',
      'Write what “enough” means for you: a number and a lifestyle.', ['money', 'contentment', 'comparison', 'greed']),
  Teaching('pom_compound', 'Idea from “The Psychology of Money” (Morgan Housel)', 'Wealth comes from saving consistently and letting compounding work for a long time. Time in the market beats timing it.',
      'Automate a monthly investment so you never have to decide again.', ['investing', 'compounding', 'saving', 'wealth', 'patience']),
  Teaching('pom_hidden', 'Idea from “The Psychology of Money” (Morgan Housel)', 'Wealth is what you don’t see: the car not bought, the money not spent. Being rich is spending; being wealthy is keeping.',
      'Skip one status purchase this week and invest that money.', ['money', 'saving', 'spending', 'comparison']),
  Teaching('richdad_assets', 'Idea from “Rich Dad Poor Dad” (Robert Kiyosaki)', 'Buy assets that put money in your pocket, not liabilities that take it out. Pay yourself first.',
      'List your assets and liabilities on one page today.', ['money', 'wealth', 'investing', 'debt']),
  Teaching('naval_leverage', 'Idea from “The Almanack of Naval Ravikant”', 'Earn with your mind, not your time: build specific knowledge and use leverage like code and media that work while you sleep.',
      'Spend 30 minutes on a side project: a small game, tool or post.', ['wealth', 'career', 'coding', 'skills', 'money']),
  Teaching('naval_long', 'Idea from “The Almanack of Naval Ravikant”', 'Play long-term games with long-term people. All returns in life come from compound interest.',
      'Invest time today in one relationship or skill you’ll keep for 10 years.', ['relationships', 'career', 'wealth', 'patience']),
  Teaching('bogle_index', 'Idea from “The Little Book of Common Sense Investing” (John Bogle)', 'Don’t look for the needle in the haystack; buy the haystack. Low-cost index funds beat most stock-pickers over time.',
      'Compare the expense ratio of your funds; prefer low-cost index funds.', ['investing', 'stocks', 'money', 'risk']),
  Teaching('graham_mr', 'Idea from “The Intelligent Investor” (Benjamin Graham)', 'The market is a moody partner, “Mr Market”. Use his panic and excitement; don’t be ruled by them. Always keep a margin of safety.',
      'When markets fall, don’t sell in panic; stick to your SIP.', ['investing', 'stocks', 'fear', 'patience', 'money']),
  Teaching('7h_end', 'Idea from “The 7 Habits of Highly Effective People” (Stephen Covey)', 'Begin with the end in mind; then put first things first: important before urgent.',
      'Write tomorrow’s top 3 tasks tonight, most important first.', ['planning', 'purpose', 'time', 'productivity', 'procrastination']),
  Teaching('7h_saw', 'Idea from “The 7 Habits of Highly Effective People” (Stephen Covey)', 'Sharpen the saw: renew body, mind, heart and spirit regularly, or your effectiveness wears down.',
      'Do one renewal today: exercise, reading, a call, or meditation.', ['health', 'balance', 'burnout', 'stress']),
  Teaching('mindset', 'Idea from “Mindset” (Carol Dweck)', 'With a growth mindset, ability grows with effort; failure is information, not identity.',
      'Replace “I’m bad at maths” with “I’m bad at maths yet”, and solve one problem.', ['learning', 'failure', 'maths', 'confidence', 'growth']),
  Teaching('frankl', 'Idea from “Man’s Search for Meaning” (Viktor Frankl)', 'Everything can be taken from a person but one thing: the freedom to choose one’s attitude in any situation.',
      'In today’s hardest moment, consciously choose your response.', ['purpose', 'sadness', 'stress', 'meaning', 'grief']),
  Teaching('ikigai', 'Idea from “Ikigai” (García & Miralles)', 'A reason to wake up lies where what you love, what you’re good at, what the world needs and what you can be paid for overlap.',
      'Draw the four circles and write one thing in each.', ['purpose', 'career', 'meaning', 'motivation']),
  Teaching('now', 'Idea from “The Power of Now” (Eckhart Tolle)', 'Most suffering lives in thoughts about the past and future. Peace is found in the present moment.',
      'For one routine task today (eating, walking), give it your full attention.', ['anxiety', 'peace', 'mind', 'stress', 'overthinking']),
];

// ───────────── Understanding the user ─────────────

/// Words (English + Hinglish) → topics.
const _topicWords = <String, List<String>>{
  'anxiety': ['anxiety', 'anxious', 'tension', 'chinta', 'pareshan*', 'pareshaan*', 'worried', 'worry', 'nervous', 'overthink*', 'ghabra*'],
  'stress': ['stress', 'stressed', 'pressure', 'burnout', 'thak', 'tired', 'exhausted', 'overwhelmed', 'deadline'],
  'sadness': ['sad', 'udaas', 'udas', 'dukh', 'dukhi', 'depressed', 'low', 'cry', 'rona', 'hurt', 'broken', 'upset'],
  'anger': ['angry', 'anger', 'gussa', 'gusse', 'naraz*', 'irritat*', 'frustrat*', 'mad', 'chidchid*'],
  'fear': ['fear', 'scared', 'dar', 'darr', 'afraid', 'bhay', 'insecure'],
  'grief': ['died', 'death', 'passed', 'maut', 'mrityu', 'grief', 'lost someone', 'miss him', 'miss her'],
  'loneliness': ['lonely', 'akela', 'alone', 'koi nahi'],
  'failure': ['fail', 'failed', 'failure', 'haar', 'reject', 'rejected', 'galti', 'mistake', 'loss'],
  'motivation': ['motivat*', 'himmat', 'inspir*', 'hope', 'give up', 'quit'],
  'laziness': ['lazy', 'aalas', 'aalsi', 'nothing to do', 'bored'],
  'procrastination': ['procrastinat*', 'kal karunga', 'kal karungi', 'delay', 'postpone', 'baad mein', 'taal'],
  'focus': ['focus*', 'concentrat*', 'dhyan', 'distract*', 'attention'],
  'scroll': ['reels', 'shorts', 'scroll', 'scrolling', 'instagram', 'phone addiction', 'social media'],
  'discipline': ['discipline', 'consistent', 'consistency', 'routine', 'self control'],
  'habits': ['habit', 'habits', 'aadat', 'daily'],
  'purpose': ['purpose', 'meaning', 'maksad', 'why am i', 'life ka', 'direction', 'lost in life'],
  'confusion': ['confused', 'confusion', 'samajh nahi', 'dilemma', 'kya karu', 'kya karun'],
  'decision': ['decide', 'decision', 'choose', 'choice', 'should i'],
  'money': ['money', 'paisa', 'paise', 'rupees', 'salary', 'income', 'kamai', 'rich', 'ameer', 'wealth', 'dhan', 'finance', 'financial'],
  'saving': ['save', 'saving', 'savings', 'bacha*', 'bachat', 'budget', 'emergency fund', 'kharcha', 'kharche'],
  'investing': ['invest*', 'sip', 'mutual fund', 'stock', 'stocks', 'share market', 'crypto', 'index fund', 'fd'],
  'debt': ['debt', 'loan', 'karz', 'karza', 'emi', 'credit card'],
  'career': ['career', 'job', 'naukri', 'office', 'boss', 'promotion', 'interview', 'resume', 'company', 'startup'],
  'work': ['work', 'kaam', 'project', 'task'],
  'learning': ['learn', 'learning', 'study', 'padhai', 'exam', 'course', 'seekh', 'book', 'tutedude'],
  'relationships': ['relationship', 'girlfriend', 'boyfriend', 'gf', 'bf', 'love', 'pyaar', 'breakup', 'partner', 'marriage', 'shaadi'],
  'family': ['family', 'parents', 'maa', 'mummy', 'papa', 'father', 'mother', 'bhai', 'behen', 'ghar'],
  'friends': ['friend', 'friends', 'dost', 'yaar'],
  'ego': ['ego', 'ghamand', 'proud', 'arrogant', 'attitude'],
  'desire': ['desire', 'want', 'craving', 'lust', 'iccha'],
  'comparison': ['compare', 'comparison', 'jealous', 'jalan', 'better than me', 'others have'],
  'peace': ['peace', 'shanti', 'sukoon', 'calm', 'relax'],
  'meditation': ['meditate', 'meditation', 'dhyan karna', 'breath', 'pranayam'],
  'faith': ['god', 'bhagwan', 'krishna', 'ram', 'shiva', 'faith', 'pray', 'prayer', 'mandir'],
  'health': ['health', 'sick', 'bimar', 'gym', 'weight', 'body', 'neend', 'sleep', 'diet'],
  'gratitude': ['grateful', 'thank', 'thanks', 'shukriya', 'blessed'],
  'success': ['success', 'safalta', 'win', 'jeet', 'achieve', 'goal'],
  'time': ['time', 'samay', 'waqt', 'late'],
  'coding': ['code', 'coding', 'bug', 'developer', 'programming'],
  'maths': ['maths', 'math', 'mathematics'],
};

enum Mood { calm, happy, sad, anxious, angry, confused, curious, motivated }

class Understanding {
  final Set<String> topics;
  final Mood mood;
  const Understanding(this.topics, this.mood);
}

Understanding understand(String text) {
  final t = ' ${text.toLowerCase()} ';
  final topics = <String>{};
  _topicWords.forEach((topic, words) {
    for (final w in words) {
      // "stem*" matches any spelling that starts with the stem (bacha* → bachaun, bachau, bachana…)
      final stem = w.endsWith('*');
      final word = RegExp.escape(stem ? w.substring(0, w.length - 1) : w);
      if (RegExp(stem ? '(?<![a-z])$word' : '(?<![a-z])$word(?![a-z])').hasMatch(t)) {
        topics.add(topic);
        break;
      }
    }
  });
  Mood mood = Mood.calm;
  if (topics.contains('anger')) {
    mood = Mood.angry;
  } else if (topics.intersection({'sadness', 'grief', 'loneliness', 'failure'}).isNotEmpty) {
    mood = Mood.sad;
  } else if (topics.intersection({'anxiety', 'stress', 'fear'}).isNotEmpty) {
    mood = Mood.anxious;
  } else if (topics.intersection({'confusion', 'decision'}).isNotEmpty) {
    mood = Mood.confused;
  } else if (topics.intersection({'gratitude', 'success'}).isNotEmpty || RegExp(r'\b(happy|khush|great|awesome|mast)\b').hasMatch(t)) {
    mood = Mood.happy;
  } else if (topics.contains('motivation')) {
    mood = Mood.motivated;
  } else if (t.contains('?') || RegExp(r'\b(what|why|how|kya|kyu|kaise|kaun)\b').hasMatch(t)) {
    mood = Mood.curious;
  }
  return Understanding(topics, mood);
}

/// Best-matching teachings for what the user said; avoids repeating recently used ones.
List<Teaching> retrieve(String text, {Set<String> recent = const {}, int n = 2}) {
  final u = understand(text);
  final words = text.toLowerCase().split(RegExp(r'[^a-zऀ-ॿ]+')).where((w) => w.length > 3).toSet();
  final scored = <(Teaching, double)>[];
  for (final (i, tc) in teachings.indexed) {
    var s = 0.0;
    for (final tag in tc.tags) {
      if (u.topics.contains(tag)) s += 3;
    }
    final hay = '${tc.mean} ${tc.src}'.toLowerCase();
    for (final w in words) {
      if (hay.contains(w)) s += 0.6;
    }
    if (recent.contains(tc.id)) s -= 4;
    s += (i * 7919 % 97) / 1000; // stable tie-break
    scored.add((tc, s));
  }
  scored.sort((a, b) => b.$2.compareTo(a.$2));
  if (scored.first.$2 < 1) {
    // Nothing specific: rotate through the core Gita teachings by day.
    final core = teachings.where((t) => t.id.startsWith('g') && !recent.contains(t.id)).toList();
    return [core[DateTime.now().difference(DateTime(2026)).inDays.abs() % core.length]];
  }
  return [for (final s in scored.take(n)) if (s.$2 >= 1) s.$1];
}

/// Today's verse for the morning brief and the Talk screen.
Teaching verseOfTheDay([DateTime? d]) {
  final day = (d ?? DateTime.now()).difference(DateTime(2026)).inDays.abs();
  return teachings[(day * 37) % teachings.length];
}
