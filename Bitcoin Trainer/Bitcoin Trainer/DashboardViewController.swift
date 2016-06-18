//
//  DashboardViewController.swift
//  Bitcoin Trainer
//
//  Created by Daniel Riehs on 8/24/15.
//  Copyright (c) 2015 Daniel Riehs. All rights reserved.
//

import UIKit
import HealthKit
import CoreData

public class DashboardViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {

    @IBOutlet weak var tableView: UITableView!

    @IBOutlet weak var balanceDisplay: UILabel!

    @IBOutlet weak var statusDisplay: UITextView!

    @IBOutlet weak var setGoalButton: UIButton!

    @IBOutlet weak var sendBitcoinButton: UIButton!

    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!

	var healthKitManager: HealthKitManager = HealthKitManager()
	var workouts = [HKWorkout]()

	//Workout dates will be displayed in this format.
	lazy var dateFormatter:NSDateFormatter = {
		let formatter = NSDateFormatter()
		formatter.timeStyle = .ShortStyle
		formatter.dateStyle = .MediumStyle
		return formatter;
	}()


	//Goals are persisted in Core Data:

	//Useful for saving data into the Core Data context.
	var sharedContext: NSManagedObjectContext {
		return CoreDataStackManager.sharedInstance().managedObjectContext!
	}


	//Bitcoin address information is persisted with NSCoding:
	
	//Defining the file path where the archived data will be stored by the NSKeyedArchiver.
	var filePath: String {
		let manager = NSFileManager.defaultManager()
		let url = manager.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first
		return url!.URLByAppendingPathComponent("bitcoinAddress").path!
	}


	public override func viewDidLoad() {
		super.viewDidLoad()
	
		//Calls the applicationWillEnterForeground function when the app transitions out of the background state. Necessary for refreshing workout data.
		NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(UIApplicationDelegate.applicationWillEnterForeground(_:)), name: UIApplicationWillEnterForegroundNotification, object: nil)

		setGoalButton.enabled = true
		sendBitcoinButton.enabled = true
		
		activityIndicator.hidden = true

		//Fetch goal from Core Data.
		Goals.sharedInstance().goals = fetchGoal()

		//If the app is being run for the first time, and there is no goal in the array, a dummy goal is created.
		if Goals.sharedInstance().goals.count == 0 {
			Goals.sharedInstance().goals.append(Goal(workoutCount: 0, prize: "No Goal Set", date: NSDate(),context: sharedContext))
			CoreDataStackManager.sharedInstance().saveContext()
			self.statusDisplay.text = Goals.sharedInstance().goals[0].prize
		}

		//Request HealthKit authorization.
		healthKitManager.authorizeHealthKit { (authorized,  error) -> Void in
			if authorized {
				print("HealthKit authorization received.")
			}
			else
			{
				print("HealthKit authorization denied!")
				if error != nil {
					print("\(error)")
				}
			}
		}

		//Unarchiving any saved Bitcoin address information that was saved with NSCoding.
		if let bitcoinAddress = NSKeyedUnarchiver.unarchiveObjectWithFile(filePath) as? BitcoinAddress {
			BitcoinAddress.sharedInstance().setProperties(bitcoinAddress.password, address: bitcoinAddress.address, guid: bitcoinAddress.guid)
			
		}

		//Generates a new Bitcoin address if one has not already been created.
		if BitcoinAddress.sharedInstance().address == "Error" {
			BitcoinAddress.sharedInstance().createProperties() { (success, errorString) in
				if success {
					dispatch_async(dispatch_get_main_queue(), { () -> Void in
						
						//A new Bitcoin address will always have a balance of 0.
						self.balanceDisplay.text = "0"
					});
				}
			}
		} else {

			//Start the activity indicator.
			activityIndicator.hidden = false

			BitcoinAddress.sharedInstance().getBalance(balanceDisplay) { (success, errorString) in

				//Stop the activity indicator.
				dispatch_async(dispatch_get_main_queue(), { () -> Void in
					self.activityIndicator.hidden = true
				});

				if !success {
					dispatch_async(dispatch_get_main_queue(), { () -> Void in
						self.balanceDisplay.text = errorString
					});
				}
			}
		}
	}


	public override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		
		refreshDashboard()
	}


	//Refreshes goal and balance information when a view controller is dismissed.
	public override func viewDidAppear(animated: Bool) {

		//Start the activity indicator.
		activityIndicator.hidden = false

		BitcoinAddress.sharedInstance().getBalance(balanceDisplay) { (success, errorString) in

			//Stop the activity indicator.
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				self.activityIndicator.hidden = true
			});

			if !success {
				dispatch_async(dispatch_get_main_queue(), { () -> Void in
					self.balanceDisplay.text = errorString
				});
			}
		}

		//Saves the Bitcoin address information.
		NSKeyedArchiver.archiveRootObject(BitcoinAddress.sharedInstance(), toFile: filePath)

		refreshDashboard()
		
	}


	func applicationWillEnterForeground(notification: NSNotification) {
		refreshDashboard()
	}


	//Refreshes workout data and checks to see if the goal has been met.
	public func refreshDashboard() {

		//Read workouts from HealthKit.
		healthKitManager.readWorkouts({ (results, error) -> Void in
			if( error != nil )
			{
				print("Error reading workouts: \(error.localizedDescription)")
				return;
			}
			else
			{
				print("Workouts read successfully!")
			}

			//Save workouts into arra.
			self.workouts = results as! [HKWorkout]
			
			//Refresh tableview in main thread.
			dispatch_async(dispatch_get_main_queue(), { () -> Void in
				self.tableView.reloadData()
				
				//If a goal has been set, check to see if it has been met.
				if Goals.sharedInstance().goals[0].prize != "No Goal Set" {
					
					//The goal has been met.
					if Int32(self.workouts.count) >= Goals.sharedInstance().goals[0].workoutCount {
						self.setGoalButton.enabled = true
						self.sendBitcoinButton.enabled = true
						self.statusDisplay.text = "You completed \(Goals.sharedInstance().goals[0].workoutCount) workouts. Buy your \(Goals.sharedInstance().goals[0].prize)!"
					
					//The goal has not yet been met.
					} else {
						self.setGoalButton.enabled = false
						self.sendBitcoinButton.enabled = false
						self.statusDisplay.text = "Complete \(Goals.sharedInstance().goals[0].workoutCount) workouts and buy your \(Goals.sharedInstance().goals[0].prize)!"
					}
				}
			});
			
		})
	}


	public func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return  workouts.count
	}


	public func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

		let cell = tableView.dequeueReusableCellWithIdentifier("workoutcellid", forIndexPath: indexPath)

		//Get workout for the row. Display the workout date.
		let workout  = workouts[indexPath.row]
		let startDate = dateFormatter.stringFromDate(workout.startDate)
		cell.textLabel!.text = startDate

		return cell
	}


	//Loads the goal from Core Data.
	func fetchGoal() -> [Goal] {

		let error: NSErrorPointer = nil
		let fetchRequest = NSFetchRequest(entityName: "Goal")
		let results: [AnyObject]?
		do {
			results = try sharedContext.executeFetchRequest(fetchRequest)
		} catch let error1 as NSError {
			error.memory = error1
			results = nil
		}

		if error != nil {
			print("Error in fetchGoal(): \(error)")
		}

		return results as! [Goal]
	}


	public override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
	}
}
