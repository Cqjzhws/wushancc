import UIKit

class MainViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    private let versionCode = AnimationHelper.currentVersion
    private var tableView = UITableView()
    private var hasRootPermission = false
    private var config = AnimationHelper.currentConfig()
    private var displayLink: CADisplayLink?
    private var fps: Double = 0
    private var lastTS: CFTimeInterval = 0
    private var frameCount = 0

    // Sections
    private enum Section: Int, CaseIterable {
        case preset = 0
        case speed
        case smart
        case categories
        case blacklist
        case monitor
        case actions
        case advanced
        case about
    }

    private let sectionTitles = [
        NSLocalizedString("Preset", comment: ""),
        NSLocalizedString("Speed", comment: ""),
        NSLocalizedString("SmartScale", comment: ""),
        NSLocalizedString("Categories", comment: ""),
        NSLocalizedString("Blacklist", comment: ""),
        NSLocalizedString("Monitor", comment: ""),
        NSLocalizedString("Actions", comment: ""),
        NSLocalizedString("Advanced", comment: ""),
        NSLocalizedString("About", comment: "")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = NSLocalizedString("CFBundleDisplayName", comment: "")

        if #available(iOS 15.0, *) {
            tableView = UITableView(frame: .zero, style: .insetGrouped)
        } else {
            tableView = UITableView(frame: .zero, style: .grouped)
        }

        hasRootPermission = AnimationHelper.checkInstallPermission()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")

        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leftAnchor.constraint(equalTo: view.leftAnchor),
            tableView.rightAnchor.constraint(equalTo: view.rightAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        startFPSMonitor()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !hasRootPermission {
            showTextAlert(title: NSLocalizedString("NeedPermissionsTitle", comment: ""),
                          message: NSLocalizedString("NeedPermissionsMessage", comment: ""))
        }
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - FPS

    private func startFPSMonitor() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        frameCount += 1
        if lastTS == 0 { lastTS = link.timestamp }
        let elapsed = link.timestamp - lastTS
        if elapsed >= 0.5 {
            fps = Double(frameCount) / elapsed
            frameCount = 0
            lastTS = link.timestamp
            // 刷新 FPS cell
            let idx = IndexPath(row: 0, section: Section.monitor.rawValue)
            if let cell = tableView.cellForRow(at: idx) {
                cell.detailTextLabel?.text = String(format: "%.0f FPS", fps)
            }
        }
    }

    // MARK: - DataSource

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let s = Section(rawValue: section) else { return 0 }
        switch s {
        case .preset:     return SpeedPreset.allCases.count
        case .speed:      return 1
        case .smart:      return 3   // min duration / instant / reduce motion
        case .categories: return config.categories.count
        case .blacklist:  return config.blacklist.count + 1
        case .monitor:    return 1
        case .actions:    return 2
        case .advanced:   return 1
        case .about:      return 3
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        return sectionTitles[s.rawValue]
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let s = Section(rawValue: section) else { return nil }
        switch s {
        case .speed:   return NSLocalizedString("SpeedFooter", comment: "")
        case .smart:   return NSLocalizedString("SmartFooter", comment: "")
        case .advanced:return NSLocalizedString("AdvancedFooter", comment: "")
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let s = Section(rawValue: indexPath.section) else {
            return UITableViewCell(style: .default, reuseIdentifier: "Cell")
        }

        switch s {
        case .preset:
            let preset = SpeedPreset.allCases[indexPath.row]
            let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "Cell")
            cell.textLabel?.text = preset.displayName
            cell.detailTextLabel?.text = String(format: "系数 %.2f", preset.viewAnimationFactor)
            cell.accessoryType = (preset.viewAnimationFactor == config.factor && !config.instantMode && !config.reduceMotion) ? .checkmark : .none
            return cell

        case .speed:
            let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
            cell.textLabel?.text = NSLocalizedString("Factor", comment: "")
            let slider = UISlider(frame: CGRect(x: 0, y: 0, width: 200, height: 30))
            slider.minimumValue = 0.01
            slider.maximumValue = 2.0
            slider.value = Float(config.factor)
            slider.addTarget(self, action: #selector(factorChanged(_:)), for: .valueChanged)
            cell.accessoryView = slider
            return cell

        case .smart:
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
                cell.textLabel?.text = NSLocalizedString("MinDuration", comment: "")
                cell.detailTextLabel?.text = String(format: "%.0f ms", config.minDurationMs)
                cell.accessoryType = .disclosureIndicator
                return cell
            } else if indexPath.row == 1 {
                return switchCell(title: NSLocalizedString("InstantMode", comment: ""),
                                  on: config.instantMode, tag: 100)
            } else {
                return switchCell(title: NSLocalizedString("ReduceMotion", comment: ""),
                                  on: config.reduceMotion, tag: 101)
            }

        case .categories:
            let keys = Array(config.categories.keys).sorted()
            let key = keys[indexPath.row]
            return switchCell(title: key, on: config.categories[key] ?? true, tag: 200 + indexPath.row)

        case .blacklist:
            if indexPath.row < config.blacklist.count {
                let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
                cell.textLabel?.text = config.blacklist[indexPath.row]
                cell.textLabel?.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                cell.accessoryType = .none
                return cell
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
                cell.textLabel?.text = NSLocalizedString("AddBlacklist", comment: "")
                cell.textLabel?.textColor = .systemBlue
                cell.accessoryType = .disclosureIndicator
                return cell
            }

        case .monitor:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
            cell.textLabel?.text = NSLocalizedString("CurrentFPS", comment: "")
            cell.detailTextLabel?.text = String(format: "%.0f FPS", fps)
            cell.selectionStyle = .none
            return cell

        case .actions:
            let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
            if indexPath.row == 0 {
                cell.textLabel?.text = NSLocalizedString("Apply", comment: "")
                cell.textLabel?.textColor = hasRootPermission ? .systemBlue : .lightGray
            } else {
                cell.textLabel?.text = NSLocalizedString("RestoreDefault", comment: "")
                cell.textLabel?.textColor = hasRootPermission ? .systemRed : .lightGray
            }
            return cell

        case .advanced:
            let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
            cell.textLabel?.text = NSLocalizedString("AdvancedTip", comment: "")
            cell.accessoryType = .disclosureIndicator
            return cell

        case .about:
            if indexPath.row == 0 {
                let cell = UITableViewCell(style: .value1, reuseIdentifier: "Cell")
                cell.textLabel?.text = NSLocalizedString("Version", comment: "")
                cell.detailTextLabel?.text = versionCode
                cell.selectionStyle = .none
                return cell
            } else if indexPath.row == 1 {
                let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
                cell.textLabel?.text = "GitHub"
                cell.accessoryType = .disclosureIndicator
                return cell
            } else {
                let cell = UITableViewCell(style: .default, reuseIdentifier: "Cell")
                cell.textLabel?.text = NSLocalizedString("Reference", comment: "")
                cell.accessoryType = .disclosureIndicator
                return cell
            }
        }
    }

    // MARK: - Switch cell helper

    private func switchCell(title: String, on: Bool, tag: Int) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: "SwitchCell")
        cell.textLabel?.text = NSLocalizedString(title, comment: "")
        let sw = UISwitch()
        sw.isOn = on
        sw.tag = tag
        sw.addTarget(self, action: #selector(toggleChanged(_:)), for: .valueChanged)
        cell.accessoryView = sw
        cell.selectionStyle = .none
        return cell
    }

    // MARK: - Actions

    @objc private func factorChanged(_ slider: UISlider) {
        config.factor = Double(slider.value)
        // 关闭 instant/reduce 当手动调系数
        config.instantMode = false
        config.reduceMotion = false
        tableView.reloadSections([Section.preset.rawValue, Section.smart.rawValue], with: .none)
    }

    @objc private func toggleChanged(_ sw: UISwitch) {
        switch sw.tag {
        case 100: config.instantMode = sw.isOn
        case 101: config.reduceMotion = sw.isOn
        default:
            if sw.tag >= 200 {
                let keys = Array(config.categories.keys).sorted()
                let idx = sw.tag - 200
                if idx < keys.count {
                    config.categories[keys[idx]] = sw.isOn
                }
            }
        }
    }

    // MARK: - Delegate

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let s = Section(rawValue: indexPath.section) else { return }

        switch s {
        case .preset:
            let p = SpeedPreset.allCases[indexPath.row]
            config.factor = p.viewAnimationFactor
            config.instantMode = false
            config.reduceMotion = false
            tableView.reloadData()

        case .smart:
            if indexPath.row == 0 { showMinDurationPicker() }

        case .blacklist:
            if indexPath.row == config.blacklist.count {
                showAddBlacklist()
            } else {
                // 点击删除
                let item = config.blacklist[indexPath.row]
                let alert = UIAlertController(title: NSLocalizedString("RemoveBlacklist", comment: ""),
                                              message: item, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("Remove", comment: ""), style: .destructive) { _ in
                    self.config.blacklist.remove(at: indexPath.row)
                    self.tableView.reloadSections([Section.blacklist.rawValue], with: .automatic)
                })
                alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
                present(alert, animated: true)
            }

        case .actions:
            if !hasRootPermission { return }
            if indexPath.row == 0 { confirmApply() }
            else { confirmRestore() }

        case .advanced:
            showAdvancedTip()

        case .about:
            if indexPath.row == 1, let url = URL(string: "https://github.com/DevelopCubeLab/AnimationSpeed") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            } else if indexPath.row == 2, let url = URL(string: "https://www.feng.com/post/13871420") {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }

        default: break
        }
    }

    // MARK: - Pickers / Editors

    private func showMinDurationPicker() {
        let alert = UIAlertController(title: NSLocalizedString("MinDuration", comment: ""),
                                      message: NSLocalizedString("MinDurationMessage", comment: ""),
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.keyboardType = .numberPad
            tf.text = String(format: "%.0f", self.config.minDurationMs)
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .default) { _ in
            if let t = alert.textFields?.first?.text, let v = Double(t), v >= 0, v <= 2000 {
                self.config.minDurationMs = v
                self.tableView.reloadSections([Section.smart.rawValue], with: .none)
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func showAddBlacklist() {
        let alert = UIAlertController(title: NSLocalizedString("AddBlacklist", comment: ""),
                                      message: NSLocalizedString("AddBlacklistMessage", comment: ""),
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "com.example.app"
            tf.text = AnimationHelper.currentBundleID()
        }
        alert.addAction(UIAlertAction(title: NSLocalizedString("Add", comment: ""), style: .default) { _ in
            if let t = alert.textFields?.first?.text, !t.isEmpty {
                if !self.config.blacklist.contains(t) {
                    self.config.blacklist.append(t)
                    self.tableView.reloadSections([Section.blacklist.rawValue], with: .automatic)
                }
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func confirmApply() {
        let alert = UIAlertController(title: NSLocalizedString("Alert", comment: ""),
                                      message: NSLocalizedString("ConfirmApplyMessage", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .destructive) { _ in
            if AnimationHelper.write(config: self.config) {
                self.showAlertWithAction(title: NSLocalizedString("Successful", comment: ""),
                                         message: NSLocalizedString("ConfigWritten", comment: ""),
                                         isReboot: true)
            } else {
                self.showTextAlert(title: NSLocalizedString("Failed", comment: ""),
                                   message: NSLocalizedString("SettingFailedMessage", comment: ""))
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func confirmRestore() {
        let alert = UIAlertController(title: NSLocalizedString("Alert", comment: ""),
                                      message: NSLocalizedString("ConfirmRestoreMessage", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Confirm", comment: ""), style: .destructive) { _ in
            if AnimationHelper.restoreDefault() {
                self.config = AnimationHelper.currentConfig()
                self.tableView.reloadData()
                self.showAlertWithAction(title: NSLocalizedString("Successful", comment: ""),
                                         message: NSLocalizedString("RestoreDefaultSuccessfulMessage", comment: ""),
                                         isReboot: true)
            } else {
                self.showTextAlert(title: NSLocalizedString("Failed", comment: ""),
                                   message: NSLocalizedString("SettingFailedMessage", comment: ""))
            }
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func showAdvancedTip() {
        let msg = NSLocalizedString("AdvancedTipMessage", comment: "")
        let alert = UIAlertController(title: NSLocalizedString("AdvancedTipTitle", comment: ""),
                                      message: msg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: ""), style: .default))
        present(alert, animated: true)
    }

    // MARK: - Alerts

    private func showTextAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: ""), style: .default))
        present(alert, animated: true)
    }

    private func showAlertWithAction(title: String, message: String, isReboot: Bool) {
        var msg = message + "\n"
        var confirm = UIAlertAction(title: NSLocalizedString("Respring", comment: ""), style: .destructive) { _ in
            DeviceController().respring()
        }
        if isReboot {
            msg += NSLocalizedString("AfterReboot", comment: "")
            confirm = UIAlertAction(title: NSLocalizedString("Reboot", comment: ""), style: .destructive) { _ in
                DeviceController().rebootDevice()
            }
        } else {
            msg += NSLocalizedString("AfterRespring", comment: "")
        }
        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        alert.addAction(confirm)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: ""), style: .cancel))
        present(alert, animated: true)
    }
}