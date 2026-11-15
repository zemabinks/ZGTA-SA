import UIKit

/// Browses only names supplied by the loaded local runtime clip library.
/// UITableView creates visible rows on demand, including for the full library.
final class NativeAnimationPanel: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate {
    var onPlay: ((String, Bool) -> Void)?
    var onStop: (() -> Void)?
    private var clips: [String] = []
    private var sections: [(block: String, clips: [String])] = []
    private var allBlocks: [String] = []
    private var selectedBlock: String?
    private var selectedClip: String?
    private var showingCommon = true
    private var looping = true
    private let card = UIView()
    private let titleLabel = NativeHUDTextLabel()
    private let countLabel = NativeHUDTextLabel()
    private let selectionLabel = NativeHUDTextLabel()
    private let search = UISearchBar()
    private let table = UITableView(frame: .zero, style: .plain)
    private let commonButton = NativeHUDButton(type: .system)
    private let allButton = NativeHUDButton(type: .system)
    private let blockButton = NativeHUDButton(type: .system)
    private let stopButton = NativeHUDButton(type: .system)
    private let loopSwitch = UISwitch()

    init(clips: [String] = []) {
        super.init(nibName: nil, bundle: nil)
        update(clips: clips)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(clips: [String]) {
        self.clips = Array(Set(clips.filter { !$0.isEmpty })).sorted()
        allBlocks = Array(Set(self.clips.map(Self.block))).sorted()
        if let selectedBlock, !allBlocks.contains(selectedBlock) { self.selectedBlock = nil }
        if let selectedClip, !self.clips.contains(selectedClip) { self.selectedClip = nil }
        if isViewLoaded { updateBlockMenu(); filter() }
    }
    func update(_ clips: [String]) { update(clips: clips) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        let backdrop = UIButton(type: .custom)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.accessibilityLabel = "Close animation browser"
        backdrop.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
        view.addSubview(backdrop)
        card.backgroundColor = UIColor.black.withAlphaComponent(0.94)
        card.layer.cornerRadius = 12
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        card.layer.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        titleLabel.text = "ANIMATIONS"
        titleLabel.menuFont = true; titleLabel.heavy = true
        titleLabel.font = .systemFont(ofSize: 20); titleLabel.textColor = .white
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        let close = NativeHUDButton(type: .system)
        configure(close, title: "CLOSE", selected: false)
        close.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
        card.addSubview(close)
        search.placeholder = "Search block or animation"
        search.searchBarStyle = .minimal
        search.autocorrectionType = .no; search.autocapitalizationType = .none
        search.searchTextField.textColor = .white
        search.searchTextField.font = .systemFont(ofSize: 14)
        search.searchTextField.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        search.delegate = self
        search.translatesAutoresizingMaskIntoConstraints = false
        search.accessibilityLabel = "Search available animation blocks and clips"
        card.addSubview(search)
        configure(commonButton, title: "EMOTES", selected: true)
        configure(allButton, title: "ALL CLIPS", selected: false)
        commonButton.addAction(UIAction { [weak self] _ in
            self?.showingCommon = true; self?.selectedBlock = nil
            self?.search.text = ""; self?.filter(); self?.updateBlockMenu()
        }, for: .touchUpInside)
        allButton.addAction(UIAction { [weak self] _ in self?.showingCommon = false; self?.filter() }, for: .touchUpInside)
        card.addSubview(commonButton); card.addSubview(allButton)
        configure(blockButton, title: "ALL BLOCKS", selected: false)
        blockButton.showsMenuAsPrimaryAction = true
        card.addSubview(blockButton)
        countLabel.font = .systemFont(ofSize: 12); countLabel.textColor = .lightGray
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(countLabel)
        table.backgroundColor = .clear
        table.separatorColor = UIColor.white.withAlphaComponent(0.13)
        table.dataSource = self; table.delegate = self
        table.rowHeight = 54
        table.sectionHeaderHeight = 26
        table.keyboardDismissMode = .onDrag
        table.register(NativeAnimationCell.self, forCellReuseIdentifier: "animation")
        table.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(table)
        selectionLabel.text = "SELECT A CLIP TO PREVIEW"
        selectionLabel.font = .systemFont(ofSize: 12); selectionLabel.textColor = .white
        selectionLabel.numberOfLines = 2
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(selectionLabel)
        let loopLabel = NativeHUDTextLabel()
        loopLabel.text = "LOOP"; loopLabel.textColor = .white
        loopLabel.font = .systemFont(ofSize: 13)
        loopLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(loopLabel)
        loopSwitch.isOn = looping
        loopSwitch.translatesAutoresizingMaskIntoConstraints = false
        loopSwitch.accessibilityLabel = "Loop animation"
        loopSwitch.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.looping = self.loopSwitch.isOn
            if let clip = self.selectedClip { self.onPlay?(clip, self.looping) }
        }, for: .valueChanged)
        card.addSubview(loopSwitch)
        configure(stopButton, title: "STOP", selected: false)
        stopButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.selectedClip = nil; self.selectionLabel.text = "ANIMATION STOPPED"
            self.table.reloadData(); self.onStop?()
        }, for: .touchUpInside)
        card.addSubview(stopButton)
        NSLayoutConstraint.activate([
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            card.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            card.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.54),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -8),
            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 75),
            close.heightAnchor.constraint(equalToConstant: 30),
            search.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
            search.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
            search.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 2),
            search.heightAnchor.constraint(equalToConstant: 42),
            commonButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            commonButton.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 4),
            commonButton.widthAnchor.constraint(equalTo: allButton.widthAnchor),
            commonButton.heightAnchor.constraint(equalToConstant: 32),
            allButton.leadingAnchor.constraint(equalTo: commonButton.trailingAnchor, constant: 6),
            allButton.topAnchor.constraint(equalTo: commonButton.topAnchor),
            allButton.heightAnchor.constraint(equalTo: commonButton.heightAnchor),
            allButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            blockButton.leadingAnchor.constraint(equalTo: commonButton.leadingAnchor),
            blockButton.trailingAnchor.constraint(equalTo: allButton.trailingAnchor),
            blockButton.topAnchor.constraint(equalTo: commonButton.bottomAnchor, constant: 4),
            blockButton.heightAnchor.constraint(equalToConstant: 30),
            countLabel.leadingAnchor.constraint(equalTo: commonButton.leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: allButton.trailingAnchor),
            countLabel.topAnchor.constraint(equalTo: blockButton.bottomAnchor, constant: 5),
            countLabel.heightAnchor.constraint(equalToConstant: 16),
            table.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            table.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -6),
            table.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 2),
            table.bottomAnchor.constraint(equalTo: selectionLabel.topAnchor, constant: -4),
            selectionLabel.leadingAnchor.constraint(equalTo: commonButton.leadingAnchor),
            selectionLabel.trailingAnchor.constraint(equalTo: allButton.trailingAnchor),
            selectionLabel.bottomAnchor.constraint(equalTo: loopSwitch.topAnchor, constant: -5),
            selectionLabel.heightAnchor.constraint(equalToConstant: 30),
            loopLabel.leadingAnchor.constraint(equalTo: commonButton.leadingAnchor),
            loopLabel.centerYAnchor.constraint(equalTo: loopSwitch.centerYAnchor),
            loopSwitch.leadingAnchor.constraint(equalTo: loopLabel.trailingAnchor, constant: 8),
            loopSwitch.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -10),
            stopButton.trailingAnchor.constraint(equalTo: allButton.trailingAnchor),
            stopButton.centerYAnchor.constraint(equalTo: loopSwitch.centerYAnchor),
            stopButton.heightAnchor.constraint(equalToConstant: 32),
            stopButton.widthAnchor.constraint(equalToConstant: 85)
        ])
        updateBlockMenu(); filter()
    }

    private func configure(_ button: NativeHUDButton, title: String, selected: Bool) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = selected ? .black : .white
        config.background.backgroundColor = selected ? .white : UIColor.white.withAlphaComponent(0.12)
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        button.configuration = config
        button.translatesAutoresizingMaskIntoConstraints = false
    }
    private static func block(_ name: String) -> String {
        name.split(separator: "/", maxSplits: 1).dropLast().first.map(String.init) ?? "other"
    }
    private static func common(_ name: String) -> Bool {
        let name = name.lowercased()
        let terms = ["dance", "wave", "chat", "handsup", "hands_up", "laugh", "smok", "sit", "idle", "hug", "kiss"]
        return terms.contains { name.contains($0) }
    }
    private func updateBlockMenu() {
        let all = UIAction(title: "ALL BLOCKS", state: selectedBlock == nil ? .on : .off) { [weak self] _ in
            self?.selectedBlock = nil; self?.filter(); self?.updateBlockMenu()
        }
        blockButton.menu = UIMenu(children: [all] + allBlocks.map { block in
            UIAction(title: block.uppercased(), state: selectedBlock == block ? .on : .off) { [weak self] _ in
                self?.selectedBlock = block; self?.showingCommon = false
                self?.filter(); self?.updateBlockMenu()
            }
        })
        configure(blockButton, title: selectedBlock?.uppercased() ?? "ALL BLOCKS", selected: false)
    }
    private func filter() {
        let query = (search.text ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let choices = clips.filter { name in
            let searchable = name.lowercased().replacingOccurrences(of: "_", with: " ")
            let matches = terms.allSatisfy { searchable.contains($0.replacingOccurrences(of: "_", with: " ")) }
            return matches && (selectedBlock == nil || Self.block(name) == selectedBlock) &&
                (!showingCommon || !query.isEmpty || Self.common(name))
        }
        let grouped = Dictionary(grouping: choices, by: Self.block)
        sections = grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
        countLabel.text = clips.isEmpty ? "LOADING LOCAL ANIMATIONS..." :
            "\(choices.count) MATCHES / \(clips.count) AVAILABLE"
        configure(commonButton, title: "EMOTES", selected: showingCommon && query.isEmpty)
        configure(allButton, title: "ALL CLIPS", selected: !showingCommon || !query.isEmpty)
        table.reloadData()
        if choices.isEmpty && !clips.isEmpty {
            let empty = NativeHUDTextLabel(); empty.text = "NO MATCHING ANIMATION"
            empty.textColor = .white; empty.textAlignment = .center; empty.font = .systemFont(ofSize: 14)
            table.backgroundView = empty
        } else { table.backgroundView = nil }
    }
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sections[section].clips.count }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = NativeHUDTextLabel()
        header.text = "  " + sections[section].block.uppercased()
        header.menuFont = true; header.heavy = true
        header.font = .systemFont(ofSize: 14); header.textColor = .white
        header.backgroundColor = UIColor(white: 0.12, alpha: 0.98)
        return header
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "animation", for: indexPath) as! NativeAnimationCell
        let clip = sections[indexPath.section].clips[indexPath.row]
        cell.update(clip, selected: clip == selectedClip)
        return cell
    }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let clip = sections[indexPath.section].clips[indexPath.row]
        selectedClip = clip
        selectionLabel.text = clip.uppercased()
        search.resignFirstResponder()
        onPlay?(clip, looping)
        table.reloadData()
    }
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) { filter() }
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) { searchBar.resignFirstResponder() }
    @objc private func closePanel() { dismiss(animated: true) }
}

private final class NativeAnimationCell: UITableViewCell {
    private let nameLabel = NativeHUDTextLabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        nameLabel.font = .systemFont(ofSize: 14); nameLabel.textColor = .white
        nameLabel.numberOfLines = 2; nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 9),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -9),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
        ])
        let selected = UIView(); selected.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        selectedBackgroundView = selected
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func update(_ clip: String, selected: Bool) {
        let display = clip.split(separator: "/", maxSplits: 1).last.map(String.init) ?? clip
        nameLabel.text = (selected ? "PLAYING - " : "") + display.replacingOccurrences(of: "_", with: " ").uppercased()
        nameLabel.textColor = selected ? UIColor(red: 172/255, green: 203/255, blue: 241/255, alpha: 1) : .white
        accessibilityLabel = clip
        accessibilityTraits = selected ? [.button, .selected] : [.button]
    }
}
